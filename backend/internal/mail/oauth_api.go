package mail

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"email/backend/internal/model"
)

const (
	gmailInitialSyncLimit = 50
	gmailFetchWorkers     = 4
	gmailSyncCursorPrefix = "gmail:history:"
)

var oauthHTTPClient = &http.Client{Timeout: 25 * time.Second}

type oauthToken struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token,omitempty"`
	TokenType    string `json:"token_type,omitempty"`
	Scope        string `json:"scope,omitempty"`
	ExpiresIn    int    `json:"expires_in,omitempty"`
	ExpiresAt    int64  `json:"expires_at,omitempty"`
}

func (c OAuthAPIConnector) Sync(ctx context.Context, account model.Account) error {
	started := time.Now()
	slog.Info("oauth sync started", "provider", c.provider, "account_id", account.ID, "email", account.Email)
	if c.db == nil {
		return errors.New("oauth connector store is not configured")
	}
	folder, err := folderByRole(c.db, account.ID, "inbox")
	if err != nil {
		return err
	}
	token, err := c.authorizedToken(ctx, account)
	if err != nil {
		return err
	}
	switch c.provider {
	case model.ProviderGmail:
		if err := c.syncGmail(ctx, account, folder, token.AccessToken); err != nil {
			slog.Error("oauth sync failed", "provider", c.provider, "account_id", account.ID, "email", account.Email, "error", err)
			return err
		}
	case model.ProviderOutlook:
		if err := c.syncOutlook(ctx, account, folder, token.AccessToken); err != nil {
			slog.Error("oauth sync failed", "provider", c.provider, "account_id", account.ID, "email", account.Email, "error", err)
			return err
		}
	default:
		return errors.New("unsupported oauth provider")
	}
	slog.Info("oauth sync completed", "provider", c.provider, "account_id", account.ID, "email", account.Email, "duration_ms", time.Since(started).Milliseconds())
	return nil
}

func (c OAuthAPIConnector) authorizedToken(ctx context.Context, account model.Account) (oauthToken, error) {
	var token oauthToken
	if err := json.Unmarshal([]byte(account.Password), &token); err != nil {
		return token, fmt.Errorf("读取 OAuth token 失败，请重新授权: %w", err)
	}
	if token.AccessToken == "" {
		return token, errors.New("账号缺少 OAuth access token，请重新授权")
	}
	if token.ExpiresAt == 0 || time.Until(time.Unix(token.ExpiresAt, 0)) > 90*time.Second {
		return token, nil
	}
	slog.Info("oauth token refresh started", "provider", c.provider, "account_id", account.ID, "email", account.Email)
	if token.RefreshToken == "" {
		return token, errors.New("OAuth token 已过期且缺少 refresh token，请重新授权")
	}
	refreshed, err := c.refreshToken(ctx, token)
	if err != nil {
		return token, err
	}
	if refreshed.RefreshToken == "" {
		refreshed.RefreshToken = token.RefreshToken
	}
	data, err := json.Marshal(refreshed)
	if err != nil {
		return token, err
	}
	account.Password = string(data)
	c.db.UpdateAccount(account)
	slog.Info("oauth token refresh completed", "provider", c.provider, "account_id", account.ID, "email", account.Email)
	return refreshed, nil
}

func (c OAuthAPIConnector) refreshToken(ctx context.Context, token oauthToken) (oauthToken, error) {
	settings := c.db.Settings()
	var tokenURL, clientID, clientSecret string
	switch c.provider {
	case model.ProviderGmail:
		tokenURL = "https://oauth2.googleapis.com/token"
		clientID = strings.TrimSpace(settings.GmailClientID)
		clientSecret = strings.TrimSpace(settings.GmailClientSecret)
	case model.ProviderOutlook:
		tokenURL = "https://login.microsoftonline.com/consumers/oauth2/v2.0/token"
		clientID = strings.TrimSpace(settings.MicrosoftClientID)
		clientSecret = strings.TrimSpace(settings.MicrosoftClientSecret)
	default:
		return oauthToken{}, errors.New("unsupported oauth provider")
	}
	if clientID == "" || clientSecret == "" {
		return oauthToken{}, errors.New("刷新 OAuth token 需要 Client ID 和 Client Secret")
	}
	values := url.Values{}
	values.Set("client_id", clientID)
	values.Set("client_secret", clientSecret)
	values.Set("refresh_token", token.RefreshToken)
	values.Set("grant_type", "refresh_token")
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, tokenURL, strings.NewReader(values.Encode()))
	if err != nil {
		return oauthToken{}, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	var refreshed oauthToken
	if err := doJSON(req, &refreshed); err != nil {
		return oauthToken{}, fmt.Errorf("刷新 OAuth token 失败: %w", err)
	}
	if refreshed.AccessToken == "" {
		return oauthToken{}, errors.New("刷新 OAuth token 响应缺少 access_token")
	}
	if refreshed.ExpiresIn > 0 {
		refreshed.ExpiresAt = time.Now().Add(time.Duration(refreshed.ExpiresIn) * time.Second).Unix()
	}
	return refreshed, nil
}

func (c OAuthAPIConnector) syncGmail(ctx context.Context, account model.Account, folder model.Folder, accessToken string) error {
	if historyID, ok := parseGmailHistoryCursor(account.SyncCursor); ok {
		if err := c.syncGmailHistory(ctx, account, folder, accessToken, historyID); err != nil {
			if !isGmailHistoryExpired(err) {
				return err
			}
			slog.Warn("gmail history cursor expired, falling back to full sync", "account_id", account.ID, "email", account.Email, "history_id", historyID, "error", err)
		} else {
			return nil
		}
	}
	return c.syncGmailFull(ctx, account, folder, accessToken)
}

func (c OAuthAPIConnector) syncGmailFull(ctx context.Context, account model.Account, folder model.Folder, accessToken string) error {
	slog.Info("gmail full sync started", "account_id", account.ID, "email", account.Email, "folder_id", folder.ID, "limit", gmailInitialSyncLimit)
	historyID, err := c.fetchGmailProfileHistoryID(ctx, accessToken)
	if err != nil {
		slog.Warn("gmail profile history id fetch failed", "account_id", account.ID, "email", account.Email, "error", err)
	}
	var list gmailListResponse
	req, err := oauthGET(ctx, gmailFullListEndpoint(), accessToken)
	if err != nil {
		return err
	}
	if err := doJSON(req, &list); err != nil {
		return fmt.Errorf("拉取 Gmail 邮件列表失败: %w", err)
	}
	ids := make([]string, 0, len(list.Messages))
	for _, item := range list.Messages {
		if strings.TrimSpace(item.ID) == "" {
			continue
		}
		ids = append(ids, item.ID)
	}
	result := c.fetchAndStoreGmailMessages(ctx, account, folder, accessToken, ids, nil)
	if historyID == "" {
		historyID = result.LatestHistoryID
	}
	if result.Failed > 0 {
		return fmt.Errorf("Gmail 部分邮件拉取失败: %d", result.Failed)
	}
	c.saveGmailHistoryCursor(account, historyID)
	slog.Info("gmail full sync completed", "account_id", account.ID, "email", account.Email, "listed", len(list.Messages), "synced", result.Synced, "skipped", result.Skipped, "failed", result.Failed, "history_id", historyID)
	return nil
}

func (c OAuthAPIConnector) syncGmailHistory(ctx context.Context, account model.Account, folder model.Folder, accessToken string, startHistoryID string) error {
	slog.Info("gmail history sync started", "account_id", account.ID, "email", account.Email, "start_history_id", startHistoryID)
	var ids []string
	forceRefresh := map[string]bool{}
	removedFromInbox := map[string]bool{}
	latestHistoryID := ""
	pageToken := ""
	pages := 0
	for {
		var history gmailHistoryResponse
		req, err := oauthGET(ctx, gmailHistoryEndpoint(startHistoryID, pageToken), accessToken)
		if err != nil {
			return err
		}
		if err := doJSON(req, &history); err != nil {
			return fmt.Errorf("拉取 Gmail 增量历史失败: %w", err)
		}
		pages++
		latestHistoryID = newerGmailHistoryID(latestHistoryID, history.HistoryID)
		for _, entry := range history.History {
			latestHistoryID = newerGmailHistoryID(latestHistoryID, entry.ID)
			for _, item := range entry.MessagesAdded {
				id := strings.TrimSpace(item.Message.ID)
				if id == "" {
					continue
				}
				delete(removedFromInbox, id)
				ids = append(ids, id)
				latestHistoryID = newerGmailHistoryID(latestHistoryID, item.Message.HistoryID)
			}
			for _, item := range entry.LabelsAdded {
				id := strings.TrimSpace(item.Message.ID)
				if id == "" {
					continue
				}
				ids = append(ids, id)
				forceRefresh[id] = true
				delete(removedFromInbox, id)
				latestHistoryID = newerGmailHistoryID(latestHistoryID, item.Message.HistoryID)
			}
			for _, item := range entry.LabelsRemoved {
				id := strings.TrimSpace(item.Message.ID)
				if id == "" {
					continue
				}
				latestHistoryID = newerGmailHistoryID(latestHistoryID, item.Message.HistoryID)
				if containsString(item.LabelIDs, "INBOX") {
					removedFromInbox[id] = true
					delete(forceRefresh, id)
					continue
				}
				if removedFromInbox[id] {
					continue
				}
				ids = append(ids, id)
				forceRefresh[id] = true
			}
			for _, item := range entry.MessagesDeleted {
				id := strings.TrimSpace(item.Message.ID)
				if id == "" {
					continue
				}
				removedFromInbox[id] = true
				delete(forceRefresh, id)
				latestHistoryID = newerGmailHistoryID(latestHistoryID, item.Message.HistoryID)
			}
		}
		if strings.TrimSpace(history.NextPageToken) == "" {
			break
		}
		pageToken = history.NextPageToken
	}
	deleted := c.deleteGmailMessages(account, removedFromInbox, forceRefresh)
	fetchIDs := filterDeletedGmailIDs(ids, removedFromInbox, forceRefresh)
	result := c.fetchAndStoreGmailMessages(ctx, account, folder, accessToken, fetchIDs, forceRefresh)
	latestHistoryID = newerGmailHistoryID(latestHistoryID, result.LatestHistoryID)
	if latestHistoryID == "" {
		latestHistoryID = startHistoryID
	}
	if result.Failed > 0 {
		return fmt.Errorf("Gmail 部分增量邮件拉取失败: %d", result.Failed)
	}
	c.saveGmailHistoryCursor(account, latestHistoryID)
	slog.Info("gmail history sync completed", "account_id", account.ID, "email", account.Email, "pages", pages, "changed", len(ids), "synced", result.Synced, "skipped", result.Skipped, "deleted", deleted, "failed", result.Failed, "history_id", latestHistoryID)
	return nil
}

func (c OAuthAPIConnector) fetchGmailProfileHistoryID(ctx context.Context, accessToken string) (string, error) {
	var profile gmailProfile
	req, err := oauthGET(ctx, "https://gmail.googleapis.com/gmail/v1/users/me/profile?fields=historyId", accessToken)
	if err != nil {
		return "", err
	}
	if err := doJSON(req, &profile); err != nil {
		return "", err
	}
	return strings.TrimSpace(profile.HistoryID), nil
}

type gmailFetchResult struct {
	Synced          int
	Skipped         int
	Failed          int
	LatestHistoryID string
}

type gmailFetchOutcome struct {
	ID        string
	Message   model.Message
	HistoryID string
	Skipped   bool
	Err       error
}

func (c OAuthAPIConnector) fetchAndStoreGmailMessages(ctx context.Context, account model.Account, folder model.Folder, accessToken string, ids []string, forceRefresh map[string]bool) gmailFetchResult {
	ids = dedupeGmailIDs(ids)
	result := gmailFetchResult{}
	if len(ids) == 0 {
		return result
	}
	workerCount := gmailFetchWorkers
	if len(ids) < workerCount {
		workerCount = len(ids)
	}
	jobs := make(chan string)
	outcomes := make(chan gmailFetchOutcome)
	var wg sync.WaitGroup
	for i := 0; i < workerCount; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for id := range jobs {
				providerID := "gmail:" + id
				existing, ok := c.db.FindMessageByProvider(account.ID, providerID)
				if ok && !forceRefresh[id] {
					outcomes <- gmailFetchOutcome{ID: id, Skipped: true}
					continue
				}
				msg, historyID, err := c.fetchGmailMessage(ctx, account, folder, accessToken, id)
				if err != nil {
					if isAPIStatus(err, http.StatusNotFound, http.StatusGone) {
						outcomes <- gmailFetchOutcome{ID: id, Skipped: true}
						continue
					}
					outcomes <- gmailFetchOutcome{ID: id, Err: err}
					continue
				}
				if ok {
					msg.ID = existing.ID
					msg.CreatedAt = existing.CreatedAt
				}
				outcomes <- gmailFetchOutcome{ID: id, Message: msg, HistoryID: historyID}
			}
		}()
	}
	go func() {
		defer close(jobs)
		for _, id := range ids {
			select {
			case <-ctx.Done():
				return
			case jobs <- id:
			}
		}
	}()
	go func() {
		wg.Wait()
		close(outcomes)
	}()
	for outcome := range outcomes {
		if outcome.Skipped {
			result.Skipped++
			continue
		}
		if outcome.Err != nil {
			result.Failed++
			slog.Warn("gmail message fetch failed", "account_id", account.ID, "email", account.Email, "provider_id", outcome.ID, "error", outcome.Err)
			continue
		}
		msg := c.db.UpsertMessage(outcome.Message)
		c.broker.Publish(model.Event{Type: "message.synced", AccountID: account.ID, MessageID: msg.ID, Payload: msg})
		result.LatestHistoryID = newerGmailHistoryID(result.LatestHistoryID, outcome.HistoryID)
		result.Synced++
	}
	return result
}

func (c OAuthAPIConnector) deleteGmailMessages(account model.Account, ids map[string]bool, forceRefresh map[string]bool) int {
	deleted := 0
	for id := range ids {
		if forceRefresh[id] {
			continue
		}
		existing, ok := c.db.FindMessageByProvider(account.ID, "gmail:"+id)
		if !ok {
			continue
		}
		if err := c.db.DeleteMessage(existing.ID); err != nil {
			slog.Warn("gmail local message delete failed", "account_id", account.ID, "email", account.Email, "provider_id", id, "message_id", existing.ID, "error", err)
			continue
		}
		c.broker.Publish(model.Event{Type: "message.deleted", AccountID: account.ID, MessageID: existing.ID})
		deleted++
	}
	return deleted
}

func (c OAuthAPIConnector) saveGmailHistoryCursor(account model.Account, historyID string) {
	historyID = strings.TrimSpace(historyID)
	if historyID == "" {
		return
	}
	if current, ok := c.db.GetAccount(account.ID); ok {
		current.SyncCursor = gmailSyncCursorPrefix + historyID
		c.db.UpdateAccount(current)
		return
	}
	account.SyncCursor = gmailSyncCursorPrefix + historyID
	c.db.UpdateAccount(account)
}

func (c OAuthAPIConnector) fetchGmailMessage(ctx context.Context, account model.Account, folder model.Folder, accessToken string, id string) (model.Message, string, error) {
	var raw gmailMessage
	req, err := oauthGET(ctx, gmailMessageEndpoint(id), accessToken)
	if err != nil {
		return model.Message{}, "", err
	}
	if err := doJSON(req, &raw); err != nil {
		return model.Message{}, "", err
	}
	headers := gmailHeaders(raw.Payload.Headers)
	receivedAt := time.Now()
	if raw.InternalDate != "" {
		if ms, err := strconv.ParseInt(raw.InternalDate, 10, 64); err == nil {
			receivedAt = time.UnixMilli(ms)
		}
	} else if parsed, err := parseMailTime(headers["date"]); err == nil {
		receivedAt = parsed
	}
	bodyText, bodyHTML := gmailBody(raw.Payload)
	labels := append([]string{"inbox"}, raw.LabelIDs...)
	return model.Message{
		AccountID:  account.ID,
		FolderID:   folder.ID,
		ThreadID:   firstNonEmpty(raw.ThreadID, "gmail:"+raw.ID),
		ProviderID: "gmail:" + raw.ID,
		From:       firstAddress(parseAddressList(headers["from"])),
		To:         parseAddressList(headers["to"]),
		Cc:         parseAddressList(headers["cc"]),
		Subject:    strings.TrimSpace(headers["subject"]),
		Snippet:    firstNonEmpty(raw.Snippet, snippet(bodyText, bodyHTML)),
		BodyText:   bodyText,
		BodyHTML:   bodyHTML,
		ReceivedAt: &receivedAt,
		IsRead:     !containsString(raw.LabelIDs, "UNREAD"),
		IsStarred:  containsString(raw.LabelIDs, "STARRED"),
		Labels:     labels,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}, strings.TrimSpace(raw.HistoryID), nil
}

func (c OAuthAPIConnector) syncOutlook(ctx context.Context, account model.Account, folder model.Folder, accessToken string) error {
	slog.Info("outlook list request started", "account_id", account.ID, "email", account.Email, "folder_id", folder.ID)
	var list struct {
		Value []outlookMessage `json:"value"`
	}
	endpoint := "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages?$top=25&$orderby=receivedDateTime%20desc&$select=id,subject,bodyPreview,body,from,toRecipients,ccRecipients,receivedDateTime,isRead,flag,hasAttachments"
	req, err := oauthGET(ctx, endpoint, accessToken)
	if err != nil {
		return err
	}
	if err := doJSON(req, &list); err != nil {
		return fmt.Errorf("拉取 Outlook 邮件列表失败: %w", err)
	}
	slog.Info("outlook list request completed", "account_id", account.ID, "email", account.Email, "message_count", len(list.Value))
	synced := 0
	for _, item := range list.Value {
		receivedAt := time.Now()
		if parsed, err := time.Parse(time.RFC3339, item.ReceivedDateTime); err == nil {
			receivedAt = parsed
		}
		msg := model.Message{
			AccountID:      account.ID,
			FolderID:       folder.ID,
			ThreadID:       "outlook:" + item.ID,
			ProviderID:     "outlook:" + item.ID,
			From:           item.From.EmailAddress.toModel(),
			To:             outlookRecipients(item.ToRecipients),
			Cc:             outlookRecipients(item.CcRecipients),
			Subject:        strings.TrimSpace(item.Subject),
			Snippet:        firstNonEmpty(item.BodyPreview, snippet("", item.Body.Content)),
			BodyText:       item.BodyPreview,
			BodyHTML:       htmlBody(item.Body.ContentType, item.Body.Content),
			ReceivedAt:     &receivedAt,
			IsRead:         item.IsRead,
			IsStarred:      strings.EqualFold(item.Flag.FlagStatus, "flagged"),
			Labels:         []string{"inbox"},
			HasAttachments: item.HasAttachments,
			CreatedAt:      time.Now(),
			UpdatedAt:      time.Now(),
		}
		if existing, ok := c.db.FindMessageByProvider(account.ID, msg.ProviderID); ok {
			msg.ID = existing.ID
			msg.CreatedAt = existing.CreatedAt
		}
		msg = c.db.UpsertMessage(msg)
		c.broker.Publish(model.Event{Type: "message.synced", AccountID: account.ID, MessageID: msg.ID, Payload: msg})
		synced++
	}
	slog.Info("outlook messages synced", "account_id", account.ID, "email", account.Email, "synced", synced)
	return nil
}

func oauthGET(ctx context.Context, endpoint string, accessToken string) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "self-hosted-mail/1.0 (gzip)")
	return req, nil
}

func doJSON(req *http.Request, out any) error {
	resp, err := oauthHTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return &apiError{StatusCode: resp.StatusCode, Status: resp.Status, Body: strings.TrimSpace(string(body))}
	}
	if len(body) == 0 {
		return nil
	}
	return json.Unmarshal(body, out)
}

type apiError struct {
	StatusCode int
	Status     string
	Body       string
}

func (e *apiError) Error() string {
	if e.Body == "" {
		return e.Status
	}
	return e.Status + ": " + e.Body
}

func gmailFullListEndpoint() string {
	values := url.Values{}
	values.Set("labelIds", "INBOX")
	values.Set("maxResults", strconv.Itoa(gmailInitialSyncLimit))
	values.Set("fields", "messages(id,threadId),nextPageToken,resultSizeEstimate")
	return "https://gmail.googleapis.com/gmail/v1/users/me/messages?" + values.Encode()
}

func gmailHistoryEndpoint(startHistoryID string, pageToken string) string {
	values := url.Values{}
	values.Set("startHistoryId", startHistoryID)
	values.Set("labelId", "INBOX")
	values.Add("historyTypes", "messageAdded")
	values.Add("historyTypes", "messageDeleted")
	values.Add("historyTypes", "labelAdded")
	values.Add("historyTypes", "labelRemoved")
	values.Set("fields", "history(id,messagesAdded(message(id,threadId,labelIds,historyId)),messagesDeleted(message(id,threadId,historyId)),labelsAdded(message(id,threadId,labelIds,historyId),labelIds),labelsRemoved(message(id,threadId,labelIds,historyId),labelIds)),nextPageToken,historyId")
	if strings.TrimSpace(pageToken) != "" {
		values.Set("pageToken", pageToken)
	}
	return "https://gmail.googleapis.com/gmail/v1/users/me/history?" + values.Encode()
}

func gmailMessageEndpoint(id string) string {
	values := url.Values{}
	values.Set("format", "full")
	values.Set("fields", "id,threadId,labelIds,snippet,internalDate,historyId,payload")
	return "https://gmail.googleapis.com/gmail/v1/users/me/messages/" + url.PathEscape(id) + "?" + values.Encode()
}

func parseGmailHistoryCursor(cursor string) (string, bool) {
	cursor = strings.TrimSpace(cursor)
	if !strings.HasPrefix(cursor, gmailSyncCursorPrefix) {
		return "", false
	}
	historyID := strings.TrimSpace(strings.TrimPrefix(cursor, gmailSyncCursorPrefix))
	return historyID, historyID != ""
}

func isGmailHistoryExpired(err error) bool {
	return isAPIStatus(err, http.StatusNotFound, http.StatusGone)
}

func isAPIStatus(err error, statusCodes ...int) bool {
	var apiErr *apiError
	if !errors.As(err, &apiErr) {
		return false
	}
	for _, statusCode := range statusCodes {
		if apiErr.StatusCode == statusCode {
			return true
		}
	}
	return false
}

func dedupeGmailIDs(ids []string) []string {
	seen := map[string]bool{}
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		id = strings.TrimSpace(id)
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		out = append(out, id)
	}
	return out
}

func filterDeletedGmailIDs(ids []string, removedFromInbox map[string]bool, forceRefresh map[string]bool) []string {
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		if removedFromInbox[id] && !forceRefresh[id] {
			continue
		}
		out = append(out, id)
	}
	return out
}

func newerGmailHistoryID(current string, candidate string) string {
	current = strings.TrimSpace(current)
	candidate = strings.TrimSpace(candidate)
	if candidate == "" {
		return current
	}
	if current == "" {
		return candidate
	}
	currentValue, currentErr := strconv.ParseUint(current, 10, 64)
	candidateValue, candidateErr := strconv.ParseUint(candidate, 10, 64)
	if currentErr == nil && candidateErr == nil {
		if candidateValue > currentValue {
			return candidate
		}
		return current
	}
	if candidate > current {
		return candidate
	}
	return current
}

type gmailMessage struct {
	ID           string       `json:"id"`
	ThreadID     string       `json:"threadId"`
	LabelIDs     []string     `json:"labelIds"`
	Snippet      string       `json:"snippet"`
	InternalDate string       `json:"internalDate"`
	HistoryID    string       `json:"historyId"`
	Payload      gmailPayload `json:"payload"`
}

type gmailProfile struct {
	HistoryID string `json:"historyId"`
}

type gmailListResponse struct {
	Messages []gmailListMessage `json:"messages"`
}

type gmailListMessage struct {
	ID       string `json:"id"`
	ThreadID string `json:"threadId"`
}

type gmailHistoryResponse struct {
	History       []gmailHistoryEntry `json:"history"`
	NextPageToken string              `json:"nextPageToken"`
	HistoryID     string              `json:"historyId"`
}

type gmailHistoryEntry struct {
	ID              string                    `json:"id"`
	MessagesAdded   []gmailHistoryMessage     `json:"messagesAdded"`
	MessagesDeleted []gmailHistoryMessage     `json:"messagesDeleted"`
	LabelsAdded     []gmailHistoryLabelChange `json:"labelsAdded"`
	LabelsRemoved   []gmailHistoryLabelChange `json:"labelsRemoved"`
}

type gmailHistoryMessage struct {
	Message gmailHistoryMessageRef `json:"message"`
}

type gmailHistoryLabelChange struct {
	Message  gmailHistoryMessageRef `json:"message"`
	LabelIDs []string               `json:"labelIds"`
}

type gmailHistoryMessageRef struct {
	ID        string   `json:"id"`
	ThreadID  string   `json:"threadId"`
	LabelIDs  []string `json:"labelIds"`
	HistoryID string   `json:"historyId"`
}

type gmailPayload struct {
	MimeType string              `json:"mimeType"`
	Headers  []map[string]string `json:"headers"`
	Body     struct {
		Data string `json:"data"`
	} `json:"body"`
	Parts []gmailPayload `json:"parts"`
}

func gmailHeaders(headers []map[string]string) map[string]string {
	out := map[string]string{}
	for _, header := range headers {
		name := strings.ToLower(strings.TrimSpace(header["name"]))
		if name != "" {
			out[name] = header["value"]
		}
	}
	return out
}

func gmailBody(payload gmailPayload) (string, string) {
	var textParts []string
	var htmlParts []string
	var walk func(gmailPayload)
	walk = func(part gmailPayload) {
		decoded := decodeGmailData(part.Body.Data)
		switch strings.ToLower(part.MimeType) {
		case "text/plain":
			if strings.TrimSpace(decoded) != "" {
				textParts = append(textParts, decoded)
			}
		case "text/html":
			if strings.TrimSpace(decoded) != "" {
				htmlParts = append(htmlParts, decoded)
			}
		}
		for _, child := range part.Parts {
			walk(child)
		}
	}
	walk(payload)
	return strings.Join(textParts, "\n\n"), strings.Join(htmlParts, "\n\n")
}

func decodeGmailData(value string) string {
	if value == "" {
		return ""
	}
	data, err := base64.URLEncoding.DecodeString(value)
	if err != nil {
		data, err = base64.RawURLEncoding.DecodeString(value)
	}
	if err != nil {
		return ""
	}
	return string(data)
}

type outlookMessage struct {
	ID               string             `json:"id"`
	Subject          string             `json:"subject"`
	BodyPreview      string             `json:"bodyPreview"`
	ReceivedDateTime string             `json:"receivedDateTime"`
	IsRead           bool               `json:"isRead"`
	HasAttachments   bool               `json:"hasAttachments"`
	Body             outlookBody        `json:"body"`
	From             outlookRecipient   `json:"from"`
	ToRecipients     []outlookRecipient `json:"toRecipients"`
	CcRecipients     []outlookRecipient `json:"ccRecipients"`
	Flag             struct {
		FlagStatus string `json:"flagStatus"`
	} `json:"flag"`
}

type outlookBody struct {
	ContentType string `json:"contentType"`
	Content     string `json:"content"`
}

type outlookRecipient struct {
	EmailAddress outlookEmailAddress `json:"emailAddress"`
}

type outlookEmailAddress struct {
	Name    string `json:"name"`
	Address string `json:"address"`
}

func (a outlookEmailAddress) toModel() model.Address {
	return model.Address{Name: a.Name, Email: a.Address}
}

func outlookRecipients(items []outlookRecipient) []model.Address {
	out := make([]model.Address, 0, len(items))
	for _, item := range items {
		if strings.TrimSpace(item.EmailAddress.Address) != "" {
			out = append(out, item.EmailAddress.toModel())
		}
	}
	return out
}

func htmlBody(contentType string, content string) string {
	if strings.EqualFold(contentType, "html") {
		return content
	}
	return ""
}

func firstAddress(items []model.Address) model.Address {
	if len(items) == 0 {
		return model.Address{}
	}
	return items[0]
}

func containsString(items []string, want string) bool {
	for _, item := range items {
		if strings.EqualFold(item, want) {
			return true
		}
	}
	return false
}

func parseMailTime(value string) (time.Time, error) {
	if parsed, err := mailTimeFormats(value); err == nil {
		return parsed, nil
	}
	return time.Time{}, errors.New("invalid mail time")
}

func mailTimeFormats(value string) (time.Time, error) {
	formats := []string{time.RFC1123Z, time.RFC1123, time.RFC822Z, time.RFC822}
	var last error
	for _, format := range formats {
		parsed, err := time.Parse(format, value)
		if err == nil {
			return parsed, nil
		}
		last = err
	}
	return time.Time{}, last
}
