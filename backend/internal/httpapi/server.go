package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"email/backend/internal/auth"
	"email/backend/internal/blob"
	"email/backend/internal/config"
	"email/backend/internal/events"
	"email/backend/internal/mail"
	"email/backend/internal/model"
	"email/backend/internal/store"
)

type Server struct {
	cfg      config.Config
	auth     *auth.Service
	db       *store.Memory
	blobs    *blob.Store
	registry *mail.Registry
	broker   *events.Broker

	oauthMu       sync.RWMutex
	oauthSessions map[string]oauthSession
}

func NewServer(cfg config.Config, authSvc *auth.Service, db *store.Memory, blobs *blob.Store, registry *mail.Registry, broker *events.Broker) *Server {
	return &Server{cfg: cfg, auth: authSvc, db: db, blobs: blobs, registry: registry, broker: broker, oauthSessions: map[string]oauthSession{}}
}

type oauthSession struct {
	State       string    `json:"state"`
	Provider    string    `json:"provider"`
	Status      string    `json:"status"`
	Error       string    `json:"error,omitempty"`
	AccountID   string    `json:"account_id,omitempty"`
	Email       string    `json:"email,omitempty"`
	RedirectURI string    `json:"redirect_uri,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.health)
	mux.HandleFunc("/api/v1/auth/login", s.login)
	mux.HandleFunc("/api/v1/auth/refresh", s.refresh)
	mux.HandleFunc("/api/v1/auth/register", s.register)
	mux.HandleFunc("/api/v1/auth/check", s.checkUsers)
	mux.HandleFunc("/api/v1/events", s.events)
	mux.HandleFunc("/api/v1/webhooks/gmail", s.webhook("gmail"))
	mux.HandleFunc("/api/v1/webhooks/outlook", s.webhook("outlook"))

	mux.Handle("/api/v1/snapshot", s.requireAuth(http.HandlerFunc(s.snapshot)))
	mux.Handle("/api/v1/accounts", s.requireAuth(http.HandlerFunc(s.accounts)))
	mux.Handle("/api/v1/accounts/oauth/start", s.requireAuth(http.HandlerFunc(s.oauthStart)))
	mux.HandleFunc("/api/v1/accounts/oauth/status", s.oauthStatus)
	mux.HandleFunc("/api/v1/oauth/gmail/callback", s.oauthCallback("gmail"))
	mux.HandleFunc("/api/v1/oauth/outlook/callback", s.oauthCallback("outlook"))
	mux.Handle("/api/v1/accounts/", s.requireAuth(http.HandlerFunc(s.accountByID)))
	mux.Handle("/api/v1/folders", s.requireAuth(http.HandlerFunc(s.folders)))
	mux.Handle("/api/v1/messages", s.requireAuth(http.HandlerFunc(s.messages)))
	mux.Handle("/api/v1/messages/", s.requireAuth(http.HandlerFunc(s.messageByID)))
	mux.Handle("/api/v1/attachments/", s.requireAuth(http.HandlerFunc(s.attachmentByID)))
	mux.Handle("/api/v1/drafts", s.requireAuth(http.HandlerFunc(s.drafts)))
	mux.Handle("/api/v1/drafts/", s.requireAuth(http.HandlerFunc(s.draftByID)))
	mux.Handle("/api/v1/send", s.requireAuth(http.HandlerFunc(s.send)))
	mux.Handle("/api/v1/search", s.requireAuth(http.HandlerFunc(s.search)))
	mux.Handle("/api/v1/rules", s.requireAuth(http.HandlerFunc(s.rules)))
	mux.Handle("/api/v1/rules/", s.requireAuth(http.HandlerFunc(s.ruleByID)))
	mux.Handle("/api/v1/settings", s.requireAuth(http.HandlerFunc(s.settings)))

	return s.withRecover(s.withCORS(s.withLogging(mux)))
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "time": time.Now().UTC()})
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
		TOTP     string `json:"totp"`
	}
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	pair, err := s.auth.Login(req.Email, req.Password, req.TOTP)
	if err != nil {
		writeError(w, http.StatusUnauthorized, err)
		return
	}
	writeJSON(w, http.StatusOK, pair)
}

func (s *Server) refresh(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	pair, err := s.auth.Refresh(req.RefreshToken)
	if err != nil {
		writeError(w, http.StatusUnauthorized, err)
		return
	}
	writeJSON(w, http.StatusOK, pair)
}

func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if req.Email == "" || req.Password == "" {
		writeError(w, http.StatusBadRequest, errors.New("email and password are required"))
		return
	}
	if len(req.Password) < 8 {
		writeError(w, http.StatusBadRequest, errors.New("password must be at least 8 characters"))
		return
	}
	id, err := s.auth.Register(req.Email, req.Password)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{"id": id, "email": req.Email})
}

func (s *Server) checkUsers(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	hasUsers := s.auth.HasUsers()
	writeJSON(w, http.StatusOK, map[string]bool{"has_users": hasUsers})
}

func (s *Server) snapshot(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	writeJSON(w, http.StatusOK, s.db.Snapshot())
}

func (s *Server) accounts(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, s.db.ListAccounts())
	case http.MethodPost:
		var req struct {
			Provider    model.Provider `json:"provider"`
			Email       string         `json:"email"`
			DisplayName string         `json:"display_name"`
			Username    string         `json:"username"`
			Password    string         `json:"password"`
			IMAPHost    string         `json:"imap_host"`
			IMAPPort    int            `json:"imap_port"`
			IMAPTLS     bool           `json:"imap_tls"`
			SMTPHost    string         `json:"smtp_host"`
			SMTPPort    int            `json:"smtp_port"`
			SMTPTLS     bool           `json:"smtp_tls"`
		}
		if err := readJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		if req.Provider == "" {
			req.Provider = model.ProviderMock
		}
		if req.Provider == model.ProviderGmail || req.Provider == model.ProviderOutlook {
			writeError(w, http.StatusBadRequest, errors.New("gmail and outlook must be connected with official OAuth"))
			return
		}
		if req.DisplayName == "" {
			req.DisplayName = req.Email
		}
		account, err := mail.NormalizeAccount(model.Account{
			Provider:    req.Provider,
			Email:       req.Email,
			DisplayName: req.DisplayName,
			Username:    req.Username,
			Password:    req.Password,
			IMAPHost:    req.IMAPHost,
			IMAPPort:    req.IMAPPort,
			IMAPTLS:     req.IMAPTLS,
			SMTPHost:    req.SMTPHost,
			SMTPPort:    req.SMTPPort,
			SMTPTLS:     req.SMTPTLS,
		})
		if err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		account = s.db.CreateAccount(account)
		s.broker.Publish(model.Event{Type: "account.created", AccountID: account.ID, Payload: account})
		if account.Provider != model.ProviderMock {
			connector, ok := s.registry.For(account.Provider)
			if !ok {
				writeError(w, http.StatusBadRequest, errors.New("connector not found"))
				return
			}
			account.Status = model.AccountSyncing
			s.db.UpdateAccount(account)
			go func() {
				if err := connector.Sync(context.Background(), account); err != nil {
					account.Status = model.AccountError
					account.LastError = err.Error()
				} else {
					account.Status = model.AccountActive
					account.LastError = ""
					account.SyncCursor = strconv.FormatInt(time.Now().UnixNano(), 10)
				}
				s.db.UpdateAccount(account)
				s.broker.Publish(model.Event{Type: "account.synced", AccountID: account.ID, Payload: account})
			}()
		}
		writeJSON(w, http.StatusCreated, account)
	default:
		methodNotAllowed(w)
	}
}

func (s *Server) oauthStart(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	provider := model.Provider(strings.ToLower(strings.TrimSpace(r.URL.Query().Get("provider"))))
	state := randomState()
	settings := s.db.Settings()
	baseURL := requestBaseURL(r)
	switch provider {
	case model.ProviderGmail:
		if strings.TrimSpace(settings.GmailClientID) == "" {
			writeError(w, http.StatusBadRequest, errors.New("请先填写 Gmail OAuth Client ID"))
			return
		}
		redirectURI := callbackURL(baseURL, "/api/v1/oauth/gmail/callback")
		s.saveOAuthSession(state, provider, redirectURI)
		writeJSON(w, http.StatusOK, map[string]string{
			"provider":     string(provider),
			"state":        state,
			"auth_url":     gmailAuthURL(settings.GmailClientID, redirectURI, state),
			"redirect_uri": redirectURI,
		})
	case model.ProviderOutlook:
		if strings.TrimSpace(settings.MicrosoftClientID) == "" {
			writeError(w, http.StatusBadRequest, errors.New("请先填写 Microsoft OAuth Client ID"))
			return
		}
		redirectURI := callbackURL(baseURL, "/api/v1/oauth/outlook/callback")
		s.saveOAuthSession(state, provider, redirectURI)
		writeJSON(w, http.StatusOK, map[string]string{
			"provider":     string(provider),
			"state":        state,
			"auth_url":     outlookAuthURL(settings.MicrosoftClientID, redirectURI, state),
			"redirect_uri": redirectURI,
		})
	default:
		writeError(w, http.StatusBadRequest, errors.New("provider must be gmail or outlook"))
	}
}

func (s *Server) oauthStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	state := strings.TrimSpace(r.URL.Query().Get("state"))
	if state == "" {
		writeError(w, http.StatusBadRequest, errors.New("missing oauth state"))
		return
	}
	session, ok := s.getOAuthSession(state)
	if !ok {
		writeError(w, http.StatusNotFound, errors.New("oauth state not found"))
		return
	}
	writeJSON(w, http.StatusOK, session)
}

func (s *Server) oauthCallback(provider string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		state := strings.TrimSpace(r.URL.Query().Get("state"))
		if state == "" {
			writeError(w, http.StatusBadRequest, errors.New("missing oauth state"))
			return
		}
		if errorCode := strings.TrimSpace(r.URL.Query().Get("error")); errorCode != "" {
			errorDescription := strings.TrimSpace(r.URL.Query().Get("error_description"))
			if errorDescription == "" {
				errorDescription = errorCode
			}
			session := s.markOAuthSession(state, model.Provider(provider), "error", errorDescription)
			s.publishOAuthEvent("oauth.failed", session)
			writeOAuthHTML(w, "授权失败", provider+" OAuth 返回错误："+errorDescription, "请回到客户端重新生成授权链接。")
			return
		}
		code := strings.TrimSpace(r.URL.Query().Get("code"))
		if code == "" {
			writeError(w, http.StatusBadRequest, errors.New("missing oauth code"))
			return
		}
		session := s.markOAuthSession(state, model.Provider(provider), "callback_received", "")
		s.publishOAuthEvent("oauth.callback_received", session)
		writeOAuthHTML(w, "授权已返回后端", provider+" OAuth 回调已收到，客户端会自动显示当前状态。", "下一步会接入 token 交换和官方邮件 API 同步。现在可以关闭这个页面。")
	}
}

func (s *Server) saveOAuthSession(state string, provider model.Provider, redirectURI string) {
	now := time.Now().UTC()
	s.oauthMu.Lock()
	defer s.oauthMu.Unlock()
	s.oauthSessions[state] = oauthSession{
		State:       state,
		Provider:    string(provider),
		Status:      "pending",
		RedirectURI: redirectURI,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
}

func (s *Server) getOAuthSession(state string) (oauthSession, bool) {
	s.oauthMu.RLock()
	defer s.oauthMu.RUnlock()
	session, ok := s.oauthSessions[state]
	return session, ok
}

func (s *Server) markOAuthSession(state string, provider model.Provider, status string, message string) oauthSession {
	now := time.Now().UTC()
	s.oauthMu.Lock()
	defer s.oauthMu.Unlock()
	session, ok := s.oauthSessions[state]
	if !ok {
		session = oauthSession{
			State:     state,
			Provider:  string(provider),
			CreatedAt: now,
		}
	}
	if session.Provider == "" {
		session.Provider = string(provider)
	}
	session.Status = status
	session.Error = message
	session.UpdatedAt = now
	s.oauthSessions[state] = session
	return session
}

func (s *Server) publishOAuthEvent(eventType string, session oauthSession) {
	s.broker.Publish(model.Event{
		Type: eventType,
		Payload: map[string]any{
			"state":    session.State,
			"provider": session.Provider,
			"status":   session.Status,
			"error":    session.Error,
		},
	})
}

func writeOAuthHTML(w http.ResponseWriter, title string, body string, hint string) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = fmt.Fprintf(w, `<!doctype html><meta charset="utf-8"><title>邮箱授权</title><body style="font-family:system-ui,sans-serif;padding:32px;line-height:1.6"><h1>%s</h1><p>%s</p><p>%s</p></body>`, html.EscapeString(title), html.EscapeString(body), html.EscapeString(hint))
}

func gmailAuthURL(clientID, redirectURI, state string) string {
	values := url.Values{}
	values.Set("client_id", clientID)
	values.Set("redirect_uri", redirectURI)
	values.Set("response_type", "code")
	values.Set("scope", "https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/gmail.send")
	values.Set("access_type", "offline")
	values.Set("prompt", "consent")
	values.Set("state", state)
	return "https://accounts.google.com/o/oauth2/v2/auth?" + values.Encode()
}

func outlookAuthURL(clientID, redirectURI, state string) string {
	values := url.Values{}
	values.Set("client_id", clientID)
	values.Set("redirect_uri", redirectURI)
	values.Set("response_type", "code")
	values.Set("response_mode", "query")
	values.Set("scope", "openid profile email offline_access User.Read Mail.ReadWrite Mail.Send")
	values.Set("state", state)
	return "https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize?" + values.Encode()
}

func callbackURL(base, path string) string {
	base = strings.TrimRight(base, "/")
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}
	return base + path
}

func requestBaseURL(r *http.Request) string {
	proto := firstHeaderValue(r.Header.Get("X-Forwarded-Proto"))
	if proto == "" {
		if r.TLS != nil {
			proto = "https"
		} else {
			proto = "http"
		}
	}
	host := firstHeaderValue(r.Header.Get("X-Forwarded-Host"))
	if host == "" {
		host = r.Host
	}
	return proto + "://" + strings.TrimRight(host, "/")
}

func firstHeaderValue(value string) string {
	if idx := strings.Index(value, ","); idx >= 0 {
		value = value[:idx]
	}
	return strings.TrimSpace(value)
}

func randomState() string {
	var raw [24]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return strconv.FormatInt(time.Now().UnixNano(), 36)
	}
	return base64.RawURLEncoding.EncodeToString(raw[:])
}

func (s *Server) accountByID(w http.ResponseWriter, r *http.Request) {
	rest := strings.TrimPrefix(r.URL.Path, "/api/v1/accounts/")
	parts := strings.Split(strings.Trim(rest, "/"), "/")
	if len(parts) == 0 || parts[0] == "" {
		writeError(w, http.StatusNotFound, store.ErrNotFound)
		return
	}
	accountID := parts[0]
	if len(parts) == 2 && parts[1] == "sync" {
		s.syncAccount(w, r, accountID)
		return
	}
	switch r.Method {
	case http.MethodDelete:
		s.db.DeleteAccount(accountID)
		s.broker.Publish(model.Event{Type: "account.deleted", AccountID: accountID})
		w.WriteHeader(http.StatusNoContent)
	case http.MethodGet:
		account, ok := s.db.GetAccount(accountID)
		if !ok {
			writeError(w, http.StatusNotFound, store.ErrNotFound)
			return
		}
		writeJSON(w, http.StatusOK, account)
	default:
		methodNotAllowed(w)
	}
}

func (s *Server) syncAccount(w http.ResponseWriter, r *http.Request, accountID string) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	account, ok := s.db.GetAccount(accountID)
	if !ok {
		writeError(w, http.StatusNotFound, store.ErrNotFound)
		return
	}
	if account.Status == model.AccountSyncing {
		writeJSON(w, http.StatusAccepted, account)
		return
	}
	connector, ok := s.registry.For(account.Provider)
	if !ok {
		writeError(w, http.StatusBadRequest, errors.New("connector not found"))
		return
	}
	account.Status = model.AccountSyncing
	s.db.UpdateAccount(account)
	go func() {
		if err := connector.Sync(context.Background(), account); err != nil {
			account.Status = model.AccountError
			account.LastError = err.Error()
		} else {
			account.Status = model.AccountActive
			account.LastError = ""
			account.SyncCursor = strconv.FormatInt(time.Now().UnixNano(), 10)
		}
		s.db.UpdateAccount(account)
		s.broker.Publish(model.Event{Type: "account.synced", AccountID: account.ID, Payload: account})
	}()
	writeJSON(w, http.StatusAccepted, account)
}

func (s *Server) folders(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	writeJSON(w, http.StatusOK, s.db.ListFolders(r.URL.Query().Get("account_id")))
}

func (s *Server) messages(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	filter := store.MessageFilter{
		AccountID: r.URL.Query().Get("account_id"),
		FolderID:  r.URL.Query().Get("folder_id"),
		Query:     r.URL.Query().Get("q"),
		Limit:     limit,
	}
	writeJSON(w, http.StatusOK, s.db.ListMessages(filter))
}

func (s *Server) messageByID(w http.ResponseWriter, r *http.Request) {
	rest := strings.TrimPrefix(r.URL.Path, "/api/v1/messages/")
	parts := strings.Split(strings.Trim(rest, "/"), "/")
	if len(parts) == 0 || parts[0] == "" {
		writeError(w, http.StatusNotFound, store.ErrNotFound)
		return
	}
	id := parts[0]
	if len(parts) == 2 && parts[1] == "move" {
		s.moveMessage(w, r, id)
		return
	}
	switch r.Method {
	case http.MethodGet:
		msg, ok := s.db.GetMessage(id)
		if !ok {
			writeError(w, http.StatusNotFound, store.ErrNotFound)
			return
		}
		writeJSON(w, http.StatusOK, msg)
	case http.MethodPatch:
		var req struct {
			IsRead    *bool `json:"is_read"`
			IsStarred *bool `json:"is_starred"`
		}
		if err := readJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		msg, err := s.db.PatchMessage(id, req.IsRead, req.IsStarred)
		if err != nil {
			writeError(w, http.StatusNotFound, err)
			return
		}
		s.broker.Publish(model.Event{Type: "message.updated", AccountID: msg.AccountID, MessageID: msg.ID, Payload: msg})
		writeJSON(w, http.StatusOK, msg)
	case http.MethodDelete:
		if err := s.db.DeleteMessage(id); err != nil {
			writeError(w, http.StatusNotFound, err)
			return
		}
		s.broker.Publish(model.Event{Type: "message.deleted", MessageID: id})
		w.WriteHeader(http.StatusNoContent)
	default:
		methodNotAllowed(w)
	}
}

func (s *Server) moveMessage(w http.ResponseWriter, r *http.Request, id string) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	var req struct {
		FolderID string `json:"folder_id"`
	}
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	msg, err := s.db.MoveMessage(id, req.FolderID)
	if err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}
	s.broker.Publish(model.Event{Type: "message.moved", AccountID: msg.AccountID, MessageID: msg.ID, Payload: msg})
	writeJSON(w, http.StatusOK, msg)
}

func (s *Server) attachmentByID(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	id := strings.TrimPrefix(r.URL.Path, "/api/v1/attachments/")
	for _, msg := range s.db.ListMessages(store.MessageFilter{}) {
		for _, attachment := range msg.Attachments {
			if attachment.ID != id {
				continue
			}
			data, err := s.blobs.Load(attachment.BlobID, attachment.FileName)
			if err != nil {
				writeError(w, http.StatusNotFound, err)
				return
			}
			w.Header().Set("Content-Type", attachment.ContentType)
			w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", attachment.FileName))
			_, _ = w.Write(data)
			return
		}
	}
	writeError(w, http.StatusNotFound, store.ErrNotFound)
}

func (s *Server) drafts(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, s.db.ListDrafts())
	case http.MethodPost:
		var req model.Draft
		if err := readJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		draft := s.db.SaveDraft(req)
		s.broker.Publish(model.Event{Type: "draft.saved", AccountID: draft.AccountID, Payload: draft})
		writeJSON(w, http.StatusCreated, draft)
	default:
		methodNotAllowed(w)
	}
}

func (s *Server) draftByID(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/v1/drafts/")
	switch r.Method {
	case http.MethodPut:
		var req model.Draft
		if err := readJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		req.ID = id
		draft := s.db.SaveDraft(req)
		writeJSON(w, http.StatusOK, draft)
	case http.MethodDelete:
		s.db.DeleteDraft(id)
		w.WriteHeader(http.StatusNoContent)
	default:
		methodNotAllowed(w)
	}
}

func (s *Server) send(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	var req model.SendRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if req.AccountID == "" {
		writeError(w, http.StatusBadRequest, errors.New("account_id is required"))
		return
	}
	item := s.db.EnqueueOutbox(req)
	s.broker.Publish(model.Event{Type: "outbox.queued", AccountID: req.AccountID, Payload: item})
	writeJSON(w, http.StatusAccepted, item)
}

func (s *Server) search(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	filter := store.MessageFilter{
		AccountID: r.URL.Query().Get("account_id"),
		FolderID:  r.URL.Query().Get("folder_id"),
		Query:     r.URL.Query().Get("q"),
	}
	writeJSON(w, http.StatusOK, s.db.ListMessages(filter))
}

func (s *Server) rules(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, s.db.ListRules())
	case http.MethodPost:
		var req model.Rule
		if err := readJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		if req.Name == "" || req.Query == "" || req.Action == "" {
			writeError(w, http.StatusBadRequest, errors.New("name, query and action are required"))
			return
		}
		req.Enabled = true
		writeJSON(w, http.StatusCreated, s.db.CreateRule(req))
	default:
		methodNotAllowed(w)
	}
}

func (s *Server) ruleByID(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		methodNotAllowed(w)
		return
	}
	id := strings.TrimPrefix(r.URL.Path, "/api/v1/rules/")
	s.db.DeleteRule(id)
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) settings(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, s.db.Settings())
	case http.MethodPut:
		var req model.Settings
		if err := readJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		writeJSON(w, http.StatusOK, s.db.UpdateSettings(req))
	default:
		methodNotAllowed(w)
	}
}

func (s *Server) events(w http.ResponseWriter, r *http.Request) {
	token := bearerToken(r)
	if token == "" {
		token = r.URL.Query().Get("token")
	}
	if _, err := s.auth.Verify(token, "access"); err != nil {
		writeError(w, http.StatusUnauthorized, err)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeError(w, http.StatusInternalServerError, errors.New("streaming unsupported"))
		return
	}
	ch, unsubscribe := s.broker.Subscribe()
	defer unsubscribe()
	fmt.Fprintf(w, "event: ready\ndata: {}\n\n")
	flusher.Flush()
	heartbeat := time.NewTicker(25 * time.Second)
	defer heartbeat.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case <-heartbeat.C:
			fmt.Fprintf(w, ": heartbeat\n\n")
			flusher.Flush()
		case event := <-ch:
			data, _ := json.Marshal(event)
			fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event.Type, data)
			flusher.Flush()
		}
	}
}

func (s *Server) webhook(provider string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			methodNotAllowed(w)
			return
		}
		var payload map[string]any
		_ = readJSON(r, &payload)
		s.broker.Publish(model.Event{Type: "provider.webhook", Payload: map[string]any{"provider": provider, "payload": payload}})
		writeJSON(w, http.StatusAccepted, map[string]any{"accepted": true})
	}
}

func (s *Server) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		if _, err := s.auth.Verify(bearerToken(r), "access"); err != nil {
			writeError(w, http.StatusUnauthorized, err)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) withCORS(next http.Handler) http.Handler {
	allowed := make(map[string]struct{}, len(s.cfg.CORSAllowedOrigins))
	for _, origin := range s.cfg.CORSAllowedOrigins {
		allowed[origin] = struct{}{}
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if _, ok := allowed[origin]; ok {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, Idempotency-Key")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		slog.Info("request", "method", r.Method, "path", r.URL.Path, "duration_ms", time.Since(start).Milliseconds())
	})
}

func (s *Server) withRecover(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				slog.Error("panic", "error", err)
				writeError(w, http.StatusInternalServerError, errors.New("internal server error"))
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func bearerToken(r *http.Request) string {
	value := r.Header.Get("Authorization")
	if strings.HasPrefix(strings.ToLower(value), "bearer ") {
		return strings.TrimSpace(value[7:])
	}
	return ""
}

func readJSON(r *http.Request, target any) error {
	defer r.Body.Close()
	decoder := json.NewDecoder(io.LimitReader(r.Body, 8<<20))
	decoder.DisallowUnknownFields()
	return decoder.Decode(target)
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, map[string]any{"error": err.Error(), "status": status})
}

func methodNotAllowed(w http.ResponseWriter) {
	writeError(w, http.StatusMethodNotAllowed, errors.New("method not allowed"))
}

func WithContext(ctx context.Context, h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h.ServeHTTP(w, r.WithContext(ctx))
	})
}
