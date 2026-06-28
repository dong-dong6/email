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
	netmail "net/mail"
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
	db       store.MailStore
	blobs    *blob.Store
	registry *mail.Registry
	broker   *events.Broker

	oauthMu       sync.RWMutex
	oauthSessions map[string]oauthSession
}

func NewServer(cfg config.Config, authSvc *auth.Service, db store.MailStore, blobs *blob.Store, registry *mail.Registry, broker *events.Broker) *Server {
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

type oauthStatusResponse struct {
	State     string    `json:"state"`
	Provider  string    `json:"provider"`
	Status    string    `json:"status"`
	Error     string    `json:"error,omitempty"`
	UpdatedAt time.Time `json:"updated_at"`
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
	mux.Handle("/api/v1/accounts/oauth/status", s.requireAuth(http.HandlerFunc(s.oauthStatus)))
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
	snapshot, err := s.db.Snapshot(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	snapshot.Settings = publicSettings(snapshot.Settings)
	writeJSON(w, http.StatusOK, snapshot)
}

func (s *Server) accounts(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		accounts, err := s.db.ListAccounts(r.Context())
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		writeJSON(w, http.StatusOK, accounts)
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
		account, err = s.db.CreateAccount(r.Context(), account)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		s.broker.Publish(model.Event{Type: "account.created", AccountID: account.ID, Payload: account})
		if account.Provider != model.ProviderMock {
			connector, ok := s.registry.For(account.Provider)
			if !ok {
				writeError(w, http.StatusBadRequest, errors.New("connector not found"))
				return
			}
			account.Status = model.AccountSyncing
			if err := s.db.UpdateAccount(r.Context(), account); err != nil {
				writeError(w, http.StatusInternalServerError, err)
				return
			}
			go func() {
				ctx := context.Background()
				slog.Info("account sync started", "account_id", account.ID, "provider", account.Provider, "email", account.Email, "trigger", "account_created")
				if err := connector.Sync(ctx, account); err != nil {
					account.Status = model.AccountError
					account.LastError = err.Error()
					slog.Error("account sync failed", "account_id", account.ID, "provider", account.Provider, "email", account.Email, "error", err)
				} else {
					if refreshed, ok, err := s.db.GetAccount(ctx, account.ID); err == nil && ok {
						account = refreshed
					}
					account.Status = model.AccountActive
					account.LastError = ""
					if account.Provider != model.ProviderGmail {
						account.SyncCursor = time.Now().UTC().Format(time.RFC3339Nano)
					}
					slog.Info("account sync completed", "account_id", account.ID, "provider", account.Provider, "email", account.Email, "cursor", account.SyncCursor)
				}
				_ = s.db.UpdateAccount(ctx, account)
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
	settings, err := s.db.Settings(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	baseURL := requestBaseURL(r)
	switch provider {
	case model.ProviderGmail:
		if strings.TrimSpace(settings.GmailClientID) == "" {
			writeError(w, http.StatusBadRequest, errors.New("请先填写 Gmail OAuth Client ID"))
			return
		}
		if strings.TrimSpace(settings.GmailClientSecret) == "" {
			writeError(w, http.StatusBadRequest, errors.New("请先填写 Gmail OAuth Client Secret"))
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
		if strings.TrimSpace(settings.MicrosoftClientSecret) == "" {
			writeError(w, http.StatusBadRequest, errors.New("请先填写 Microsoft OAuth Client Secret"))
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
	writeJSON(w, http.StatusOK, publicOAuthSession(session))
}

func (s *Server) oauthCallback(provider string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		callbackProvider := model.Provider(provider)
		state := strings.TrimSpace(r.URL.Query().Get("state"))
		if state == "" {
			writeError(w, http.StatusBadRequest, errors.New("missing oauth state"))
			return
		}
		session, ok := s.getOAuthSession(state)
		if ok && !oauthSessionMatchesProvider(session, callbackProvider) {
			session = s.markOAuthSession(state, callbackProvider, "error", "OAuth state provider mismatch")
			s.publishOAuthEvent("oauth.failed", session)
			writeOAuthHTML(w, "授权流程不匹配", provider+" OAuth 回调无法完成这次授权。", "请回到客户端重新生成授权链接。")
			return
		}
		if errorCode := strings.TrimSpace(r.URL.Query().Get("error")); errorCode != "" {
			errorDescription := strings.TrimSpace(r.URL.Query().Get("error_description"))
			if errorDescription == "" {
				errorDescription = errorCode
			}
			session := s.markOAuthSession(state, callbackProvider, "error", errorDescription)
			s.publishOAuthEvent("oauth.failed", session)
			writeOAuthHTML(w, "授权失败", provider+" OAuth 返回错误："+errorDescription, "请回到客户端重新生成授权链接。")
			return
		}
		code := strings.TrimSpace(r.URL.Query().Get("code"))
		if code == "" {
			writeError(w, http.StatusBadRequest, errors.New("missing oauth code"))
			return
		}
		if !ok {
			session = s.markOAuthSession(state, callbackProvider, "error", "授权状态已失效，请回到客户端重新生成授权链接")
			s.publishOAuthEvent("oauth.failed", session)
			writeOAuthHTML(w, "授权状态已失效", "后端找不到这次 OAuth state。", "请回到客户端重新生成授权链接。")
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 25*time.Second)
		defer cancel()
		account, err := s.completeOAuth(ctx, callbackProvider, code, session.RedirectURI)
		if err != nil {
			session = s.markOAuthSession(state, callbackProvider, "error", err.Error())
			s.publishOAuthEvent("oauth.failed", session)
			writeOAuthHTML(w, "授权绑定失败", err.Error(), "请回到客户端检查 Client ID / Secret 和回调地址后重新生成授权链接。")
			return
		}
		session = s.completeOAuthSession(state, account)
		s.broker.Publish(model.Event{Type: "account.created", AccountID: account.ID, Payload: account})
		s.publishOAuthEvent("oauth.completed", session)
		writeOAuthHTML(w, "邮箱绑定完成", account.Email+" 已成功绑定到后端。", "客户端会自动刷新账号列表，现在可以关闭这个页面。")
	}
}

func oauthSessionMatchesProvider(session oauthSession, provider model.Provider) bool {
	return strings.EqualFold(strings.TrimSpace(session.Provider), string(provider))
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

func (s *Server) completeOAuthSession(state string, account model.Account) oauthSession {
	now := time.Now().UTC()
	s.oauthMu.Lock()
	defer s.oauthMu.Unlock()
	session := s.oauthSessions[state]
	session.Status = "completed"
	session.Error = ""
	session.AccountID = account.ID
	session.Email = account.Email
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

type oauthToken struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token,omitempty"`
	TokenType    string `json:"token_type,omitempty"`
	Scope        string `json:"scope,omitempty"`
	ExpiresIn    int    `json:"expires_in,omitempty"`
	ExpiresAt    int64  `json:"expires_at"`
}

func (s *Server) completeOAuth(ctx context.Context, provider model.Provider, code string, redirectURI string) (model.Account, error) {
	settings, err := s.db.Settings(ctx)
	if err != nil {
		return model.Account{}, err
	}
	var clientID, clientSecret, tokenURL string
	switch provider {
	case model.ProviderGmail:
		clientID = strings.TrimSpace(settings.GmailClientID)
		clientSecret = strings.TrimSpace(settings.GmailClientSecret)
		tokenURL = "https://oauth2.googleapis.com/token"
	case model.ProviderOutlook:
		clientID = strings.TrimSpace(settings.MicrosoftClientID)
		clientSecret = strings.TrimSpace(settings.MicrosoftClientSecret)
		tokenURL = "https://login.microsoftonline.com/consumers/oauth2/v2.0/token"
	default:
		return model.Account{}, errors.New("unsupported oauth provider")
	}
	if clientID == "" || clientSecret == "" {
		return model.Account{}, errors.New("OAuth Client ID 和 Client Secret 都必须填写")
	}
	token, err := exchangeOAuthToken(ctx, tokenURL, clientID, clientSecret, code, redirectURI)
	if err != nil {
		return model.Account{}, err
	}
	email, displayName, err := fetchOAuthProfile(ctx, provider, token.AccessToken)
	if err != nil {
		return model.Account{}, err
	}
	tokenJSON, err := json.Marshal(token)
	if err != nil {
		return model.Account{}, err
	}
	account, err := s.db.CreateAccount(ctx, model.Account{
		Provider:    provider,
		Email:       email,
		DisplayName: firstNonEmpty(displayName, email),
		Username:    email,
		Password:    string(tokenJSON),
		Status:      model.AccountActive,
	})
	return account, err
}

func exchangeOAuthToken(ctx context.Context, tokenURL string, clientID string, clientSecret string, code string, redirectURI string) (oauthToken, error) {
	values := url.Values{}
	values.Set("client_id", clientID)
	values.Set("client_secret", clientSecret)
	values.Set("code", code)
	values.Set("grant_type", "authorization_code")
	values.Set("redirect_uri", redirectURI)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, tokenURL, strings.NewReader(values.Encode()))
	if err != nil {
		return oauthToken{}, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return oauthToken{}, fmt.Errorf("交换 OAuth token 失败: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return oauthToken{}, fmt.Errorf("交换 OAuth token 失败: %s", strings.TrimSpace(string(body)))
	}
	var token oauthToken
	if err := json.Unmarshal(body, &token); err != nil {
		return oauthToken{}, fmt.Errorf("解析 OAuth token 失败: %w", err)
	}
	if token.AccessToken == "" {
		return oauthToken{}, errors.New("OAuth token 响应缺少 access_token")
	}
	if token.ExpiresIn > 0 {
		token.ExpiresAt = time.Now().Add(time.Duration(token.ExpiresIn) * time.Second).Unix()
	}
	return token, nil
}

func fetchOAuthProfile(ctx context.Context, provider model.Provider, accessToken string) (string, string, error) {
	var profileURL string
	switch provider {
	case model.ProviderGmail:
		profileURL = "https://gmail.googleapis.com/gmail/v1/users/me/profile"
	case model.ProviderOutlook:
		profileURL = "https://graph.microsoft.com/v1.0/me"
	default:
		return "", "", errors.New("unsupported oauth provider")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, profileURL, nil)
	if err != nil {
		return "", "", err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", "", fmt.Errorf("读取邮箱账号信息失败: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", "", fmt.Errorf("读取邮箱账号信息失败: %s", strings.TrimSpace(string(body)))
	}
	var raw map[string]any
	if err := json.Unmarshal(body, &raw); err != nil {
		return "", "", fmt.Errorf("解析邮箱账号信息失败: %w", err)
	}
	email := stringValue(raw, "emailAddress")
	if email == "" {
		email = stringValue(raw, "mail")
	}
	if email == "" {
		email = stringValue(raw, "userPrincipalName")
	}
	displayName := stringValue(raw, "displayName")
	if email == "" {
		return "", "", errors.New("官方 API 未返回邮箱地址")
	}
	return email, displayName, nil
}

func stringValue(raw map[string]any, key string) string {
	value, _ := raw[key].(string)
	return strings.TrimSpace(value)
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
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
		if err := s.db.DeleteAccount(r.Context(), accountID); err != nil {
			writeError(w, http.StatusNotFound, err)
			return
		}
		s.broker.Publish(model.Event{Type: "account.deleted", AccountID: accountID})
		w.WriteHeader(http.StatusNoContent)
	case http.MethodGet:
		account, ok, err := s.db.GetAccount(r.Context(), accountID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
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
	account, ok, err := s.db.GetAccount(r.Context(), accountID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
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
	if err := s.db.UpdateAccount(r.Context(), account); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	go func() {
		ctx := context.Background()
		slog.Info("account sync started", "account_id", account.ID, "provider", account.Provider, "email", account.Email, "trigger", "manual")
		if err := connector.Sync(ctx, account); err != nil {
			account.Status = model.AccountError
			account.LastError = err.Error()
			slog.Error("account sync failed", "account_id", account.ID, "provider", account.Provider, "email", account.Email, "error", err)
		} else {
			if refreshed, ok, err := s.db.GetAccount(ctx, account.ID); err == nil && ok {
				account = refreshed
			}
			account.Status = model.AccountActive
			account.LastError = ""
			if account.Provider != model.ProviderGmail {
				account.SyncCursor = time.Now().UTC().Format(time.RFC3339Nano)
			}
			slog.Info("account sync completed", "account_id", account.ID, "provider", account.Provider, "email", account.Email, "cursor", account.SyncCursor)
		}
		_ = s.db.UpdateAccount(ctx, account)
		s.broker.Publish(model.Event{Type: "account.synced", AccountID: account.ID, Payload: account})
	}()
	writeJSON(w, http.StatusAccepted, account)
}

func (s *Server) folders(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	folders, err := s.db.ListFolders(r.Context(), r.URL.Query().Get("account_id"))
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, folders)
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
	messages, err := s.db.ListMessages(r.Context(), filter)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, messages)
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
		msg, ok, err := s.db.GetMessage(r.Context(), id)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
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
		msg, err := s.db.PatchMessage(r.Context(), id, req.IsRead, req.IsStarred)
		if err != nil {
			writeError(w, http.StatusNotFound, err)
			return
		}
		s.broker.Publish(model.Event{Type: "message.updated", AccountID: msg.AccountID, MessageID: msg.ID, Payload: msg})
		writeJSON(w, http.StatusOK, msg)
	case http.MethodDelete:
		if err := s.db.DeleteMessage(r.Context(), id); err != nil {
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
	msg, err := s.db.MoveMessage(r.Context(), id, req.FolderID)
	if err != nil {
		if errors.Is(err, store.ErrInvalidAccountBoundary) {
			writeError(w, http.StatusBadRequest, err)
			return
		}
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
	messages, err := s.db.ListMessages(r.Context(), store.MessageFilter{})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	for _, msg := range messages {
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
		drafts, err := s.db.ListDrafts(r.Context())
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		writeJSON(w, http.StatusOK, drafts)
	case http.MethodPost:
		var req model.Draft
		if err := readJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		draft, err := s.db.SaveDraft(r.Context(), req)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
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
		draft, err := s.db.SaveDraft(r.Context(), req)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		writeJSON(w, http.StatusOK, draft)
	case http.MethodDelete:
		if err := s.db.DeleteDraft(r.Context(), id); err != nil {
			writeError(w, http.StatusNotFound, err)
			return
		}
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
	req.AccountID = strings.TrimSpace(req.AccountID)
	if req.AccountID == "" {
		writeError(w, http.StatusBadRequest, errors.New("account_id is required"))
		return
	}
	account, ok, err := s.db.GetAccount(r.Context(), req.AccountID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if !ok {
		writeError(w, http.StatusNotFound, store.ErrNotFound)
		return
	}
	if _, ok := s.registry.For(account.Provider); !ok {
		writeError(w, http.StatusBadRequest, errors.New("connector not found"))
		return
	}
	if err := normalizeSendRequest(&req, account); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	item, err := s.db.EnqueueOutbox(r.Context(), req)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	s.broker.Publish(model.Event{Type: "outbox.queued", AccountID: req.AccountID, Payload: item})
	writeJSON(w, http.StatusAccepted, item)
}

func normalizeSendRequest(req *model.SendRequest, account model.Account) error {
	req.AccountID = strings.TrimSpace(req.AccountID)
	req.ThreadID = strings.TrimSpace(req.ThreadID)
	req.Subject = strings.TrimSpace(req.Subject)
	if len(req.To)+len(req.Cc)+len(req.Bcc) == 0 {
		return errors.New("at least one recipient is required")
	}
	if err := normalizeAddressList("to", req.To); err != nil {
		return err
	}
	if err := normalizeAddressList("cc", req.Cc); err != nil {
		return err
	}
	if err := normalizeAddressList("bcc", req.Bcc); err != nil {
		return err
	}
	req.From = &model.Address{Name: account.DisplayName, Email: account.Email}
	return nil
}

func normalizeAddressList(field string, items []model.Address) error {
	for index := range items {
		items[index].Name = strings.TrimSpace(items[index].Name)
		items[index].Email = strings.TrimSpace(items[index].Email)
		if items[index].Email == "" {
			return fmt.Errorf("%s[%d] email is required", field, index)
		}
		parsed, err := netmail.ParseAddress(items[index].Email)
		if err != nil {
			return fmt.Errorf("invalid %s[%d] email: %w", field, index, err)
		}
		if items[index].Name == "" {
			items[index].Name = parsed.Name
		}
		items[index].Email = parsed.Address
	}
	return nil
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
	messages, err := s.db.ListMessages(r.Context(), filter)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, messages)
}

func (s *Server) rules(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		rules, err := s.db.ListRules(r.Context())
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		writeJSON(w, http.StatusOK, rules)
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
		rule, err := s.db.CreateRule(r.Context(), req)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		writeJSON(w, http.StatusCreated, rule)
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
	if err := s.db.DeleteRule(r.Context(), id); err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) settings(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		settings, err := s.db.Settings(r.Context())
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		writeJSON(w, http.StatusOK, publicSettings(settings))
	case http.MethodPut:
		var req model.Settings
		if err := readJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		current, err := s.db.Settings(r.Context())
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if strings.TrimSpace(req.GmailClientSecret) == "" {
			req.GmailClientSecret = current.GmailClientSecret
		}
		if strings.TrimSpace(req.MicrosoftClientSecret) == "" {
			req.MicrosoftClientSecret = current.MicrosoftClientSecret
		}
		updated, err := s.db.UpdateSettings(r.Context(), req)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		writeJSON(w, http.StatusOK, publicSettings(updated))
	default:
		methodNotAllowed(w)
	}
}

func publicSettings(settings model.Settings) model.Settings {
	settings.HasGmailClientSecret = strings.TrimSpace(settings.GmailClientSecret) != ""
	settings.HasMicrosoftClientSecret = strings.TrimSpace(settings.MicrosoftClientSecret) != ""
	settings.GmailClientSecret = ""
	settings.MicrosoftClientSecret = ""
	return settings
}

func publicOAuthSession(session oauthSession) oauthStatusResponse {
	return oauthStatusResponse{
		State:     session.State,
		Provider:  session.Provider,
		Status:    session.Status,
		Error:     session.Error,
		UpdatedAt: session.UpdatedAt,
	}
}

func (s *Server) events(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
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
		lrw := &loggingResponseWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(lrw, r)
		attrs := []any{
			"method", r.Method,
			"path", r.URL.Path,
			"status", lrw.status,
			"bytes", lrw.bytes,
			"duration_ms", time.Since(start).Milliseconds(),
		}
		switch {
		case lrw.status >= 500:
			slog.Error("request", attrs...)
		case lrw.status >= 400:
			slog.Warn("request", attrs...)
		default:
			slog.Debug("request", attrs...)
		}
	})
}

type loggingResponseWriter struct {
	http.ResponseWriter
	status      int
	bytes       int
	wroteHeader bool
}

func (w *loggingResponseWriter) WriteHeader(status int) {
	if w.wroteHeader {
		return
	}
	w.wroteHeader = true
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func (w *loggingResponseWriter) Write(data []byte) (int, error) {
	if !w.wroteHeader {
		w.WriteHeader(http.StatusOK)
	}
	written, err := w.ResponseWriter.Write(data)
	w.bytes += written
	return written, err
}

func (w *loggingResponseWriter) Flush() {
	if flusher, ok := w.ResponseWriter.(http.Flusher); ok {
		flusher.Flush()
	}
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
