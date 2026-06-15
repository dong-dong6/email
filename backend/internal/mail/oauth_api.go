package mail

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"email/backend/internal/model"
)

type oauthToken struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token,omitempty"`
	TokenType    string `json:"token_type,omitempty"`
	Scope        string `json:"scope,omitempty"`
	ExpiresIn    int    `json:"expires_in,omitempty"`
	ExpiresAt    int64  `json:"expires_at,omitempty"`
}

func (c OAuthAPIConnector) Sync(ctx context.Context, account model.Account) error {
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
		return c.syncGmail(ctx, account, folder, token.AccessToken)
	case model.ProviderOutlook:
		return c.syncOutlook(ctx, account, folder, token.AccessToken)
	default:
		return errors.New("unsupported oauth provider")
	}
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
	var list struct {
		Messages []struct {
			ID string `json:"id"`
		} `json:"messages"`
	}
	req, err := oauthGET(ctx, "https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=25&q=in%3Ainbox", accessToken)
	if err != nil {
		return err
	}
	if err := doJSON(req, &list); err != nil {
		return fmt.Errorf("拉取 Gmail 邮件列表失败: %w", err)
	}
	for _, item := range list.Messages {
		if strings.TrimSpace(item.ID) == "" {
			continue
		}
		msg, err := c.fetchGmailMessage(ctx, account, folder, accessToken, item.ID)
		if err != nil {
			continue
		}
		if existing, ok := c.db.FindMessageByProvider(account.ID, msg.ProviderID); ok {
			msg.ID = existing.ID
			msg.CreatedAt = existing.CreatedAt
		}
		msg = c.db.UpsertMessage(msg)
		c.broker.Publish(model.Event{Type: "message.synced", AccountID: account.ID, MessageID: msg.ID, Payload: msg})
	}
	return nil
}

func (c OAuthAPIConnector) fetchGmailMessage(ctx context.Context, account model.Account, folder model.Folder, accessToken string, id string) (model.Message, error) {
	var raw gmailMessage
	req, err := oauthGET(ctx, "https://gmail.googleapis.com/gmail/v1/users/me/messages/"+url.PathEscape(id)+"?format=full", accessToken)
	if err != nil {
		return model.Message{}, err
	}
	if err := doJSON(req, &raw); err != nil {
		return model.Message{}, err
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
	}, nil
}

func (c OAuthAPIConnector) syncOutlook(ctx context.Context, account model.Account, folder model.Folder, accessToken string) error {
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
	}
	return nil
}

func oauthGET(ctx context.Context, endpoint string, accessToken string) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	return req, nil
}

func doJSON(req *http.Request, out any) error {
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("%s: %s", resp.Status, strings.TrimSpace(string(body)))
	}
	if len(body) == 0 {
		return nil
	}
	return json.Unmarshal(body, out)
}

type gmailMessage struct {
	ID           string       `json:"id"`
	ThreadID     string       `json:"threadId"`
	LabelIDs     []string     `json:"labelIds"`
	Snippet      string       `json:"snippet"`
	InternalDate string       `json:"internalDate"`
	Payload      gmailPayload `json:"payload"`
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
