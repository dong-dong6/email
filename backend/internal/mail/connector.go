package mail

import (
	"context"
	"errors"
	"fmt"
	"net/mail"
	"strings"
	"time"

	"email/backend/internal/events"
	"email/backend/internal/model"
	"email/backend/internal/store"
)

type Connector interface {
	Provider() model.Provider
	AuthorizeURL(state string) (string, error)
	Sync(ctx context.Context, account model.Account) error
	Send(ctx context.Context, account model.Account, req model.SendRequest) (string, error)
}

type Registry struct {
	connectors map[model.Provider]Connector
}

func NewRegistry(db *store.Memory, broker *events.Broker) *Registry {
	return &Registry{connectors: map[model.Provider]Connector{
		model.ProviderMock:    MockConnector{db: db, broker: broker},
		model.ProviderGmail:   StaticConnector{provider: model.ProviderGmail, name: "Gmail API"},
		model.ProviderOutlook: StaticConnector{provider: model.ProviderOutlook, name: "Microsoft Graph Mail"},
		model.ProviderIMAP:    StaticConnector{provider: model.ProviderIMAP, name: "IMAP/SMTP"},
	}}
}

func (r *Registry) For(provider model.Provider) (Connector, bool) {
	connector, ok := r.connectors[provider]
	return connector, ok
}

type StaticConnector struct {
	provider model.Provider
	name     string
}

func (s StaticConnector) Provider() model.Provider {
	return s.provider
}

func (s StaticConnector) AuthorizeURL(state string) (string, error) {
	return "", fmt.Errorf("%s connector credentials are not configured yet", s.name)
}

func (s StaticConnector) Sync(ctx context.Context, account model.Account) error {
	return fmt.Errorf("%s sync is waiting for provider credentials", s.name)
}

func (s StaticConnector) Send(ctx context.Context, account model.Account, req model.SendRequest) (string, error) {
	return "", fmt.Errorf("%s send is waiting for provider credentials", s.name)
}

type MockConnector struct {
	db     *store.Memory
	broker *events.Broker
}

func (m MockConnector) Provider() model.Provider {
	return model.ProviderMock
}

func (m MockConnector) AuthorizeURL(state string) (string, error) {
	return "/api/v1/accounts/mock/callback?state=" + state, nil
}

func (m MockConnector) Sync(ctx context.Context, account model.Account) error {
	folders := m.db.ListFolders(account.ID)
	if len(folders) == 0 {
		return errors.New("mock account has no folders")
	}
	var inbox model.Folder
	for _, folder := range folders {
		if folder.Role == "inbox" {
			inbox = folder
			break
		}
	}
	if inbox.ID == "" {
		inbox = folders[0]
	}
	now := time.Now()
	msg := model.Message{
		AccountID: account.ID, FolderID: inbox.ID, ThreadID: store.NewID("thr"), ProviderID: store.NewID("mock"),
		From:       model.Address{Name: "Sync Robot", Email: "sync@example.com"},
		To:         []model.Address{{Email: account.Email}},
		Subject:    "同步完成 " + now.Format("15:04:05"),
		Snippet:    "这是 mock connector 生成的同步结果。",
		BodyText:   "同步任务完成。真实 Gmail/Outlook/IMAP connector 接入后，这里会写入远端邮箱增量变化。",
		BodyHTML:   "<p>同步任务完成。</p><p>真实 connector 接入后，这里会写入远端邮箱增量变化。</p>",
		ReceivedAt: &now, Labels: []string{"inbox"}, CreatedAt: now, UpdatedAt: now,
	}
	msg = m.db.UpsertMessage(msg)
	m.broker.Publish(model.Event{Type: "message.created", AccountID: account.ID, MessageID: msg.ID, Payload: msg})
	return nil
}

func (m MockConnector) Send(ctx context.Context, account model.Account, req model.SendRequest) (string, error) {
	if len(req.To) == 0 {
		return "", errors.New("missing recipient")
	}
	if _, err := mail.ParseAddress(req.To[0].Email); err != nil {
		return "", err
	}
	var sentFolder model.Folder
	for _, folder := range m.db.ListFolders(account.ID) {
		if folder.Role == "sent" {
			sentFolder = folder
			break
		}
	}
	if sentFolder.ID == "" {
		return "", errors.New("sent folder not found")
	}
	now := time.Now()
	from := model.Address{Name: account.DisplayName, Email: account.Email}
	if req.From != nil {
		from = *req.From
	}
	msg := model.Message{
		AccountID: account.ID, FolderID: sentFolder.ID, ThreadID: firstNonEmpty(req.ThreadID, store.NewID("thr")),
		ProviderID: store.NewID("mock-send"), From: from, To: req.To, Cc: req.Cc, Bcc: req.Bcc,
		Subject: strings.TrimSpace(req.Subject), Snippet: snippet(req.BodyText, req.BodyHTML),
		BodyText: req.BodyText, BodyHTML: req.BodyHTML, SentAt: &now, IsRead: true,
		Labels: []string{"sent"}, Attachments: req.Attachments, CreatedAt: now, UpdatedAt: now,
	}
	msg = m.db.UpsertMessage(msg)
	m.broker.Publish(model.Event{Type: "message.sent", AccountID: account.ID, MessageID: msg.ID, Payload: msg})
	return msg.ProviderID, nil
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func snippet(text, html string) string {
	value := strings.TrimSpace(text)
	if value == "" {
		value = stripTags(html)
	}
	if len(value) > 140 {
		return value[:140]
	}
	return value
}

func stripTags(input string) string {
	var out strings.Builder
	inTag := false
	for _, r := range input {
		switch r {
		case '<':
			inTag = true
		case '>':
			inTag = false
		default:
			if !inTag {
				out.WriteRune(r)
			}
		}
	}
	return strings.Join(strings.Fields(out.String()), " ")
}
