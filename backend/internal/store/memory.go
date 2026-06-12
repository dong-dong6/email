package store

import (
	"errors"
	"sort"
	"strings"
	"sync"
	"time"

	"email/backend/internal/blob"
	"email/backend/internal/model"
)

var ErrNotFound = errors.New("not found")

type Memory struct {
	mu       sync.RWMutex
	accounts map[string]model.Account
	folders  map[string]model.Folder
	messages map[string]model.Message
	drafts   map[string]model.Draft
	outbox   map[string]model.OutboxItem
	rules    map[string]model.Rule
	settings model.Settings
}

func NewMemory() *Memory {
	return &Memory{
		accounts: make(map[string]model.Account),
		folders:  make(map[string]model.Folder),
		messages: make(map[string]model.Message),
		drafts:   make(map[string]model.Draft),
		outbox:   make(map[string]model.OutboxItem),
		rules:    make(map[string]model.Rule),
		settings: model.Settings{
			RemoteImagesDefault: false,
			Density:             "comfortable",
			SignatureHTML:       "<p>Sent from self-hosted mail.</p>",
		},
	}
}

func (m *Memory) SeedDemo(blobs *blob.Store) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if len(m.accounts) > 0 {
		return
	}
	now := time.Now()
	account := model.Account{
		ID:          "acc_demo",
		Provider:    model.ProviderMock,
		Email:       "owner@example.com",
		DisplayName: "Personal Mail",
		Status:      model.AccountActive,
		SyncCursor:  "demo-cursor",
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	inbox := model.Folder{ID: "fld_inbox", AccountID: account.ID, ProviderID: "INBOX", Name: "Inbox", Role: "inbox", UnreadCount: 2, TotalCount: 3}
	sent := model.Folder{ID: "fld_sent", AccountID: account.ID, ProviderID: "SENT", Name: "Sent", Role: "sent", TotalCount: 1}
	drafts := model.Folder{ID: "fld_drafts", AccountID: account.ID, ProviderID: "DRAFTS", Name: "Drafts", Role: "drafts"}
	archive := model.Folder{ID: "fld_archive", AccountID: account.ID, ProviderID: "ARCHIVE", Name: "Archive", Role: "archive"}
	m.accounts[account.ID] = account
	for _, folder := range []model.Folder{inbox, sent, drafts, archive} {
		m.folders[folder.ID] = folder
	}
	m.messages["msg_welcome"] = model.Message{
		ID: "msg_welcome", AccountID: account.ID, FolderID: inbox.ID, ThreadID: "thr_welcome", ProviderID: "demo-1",
		From:       model.Address{Name: "Email System", Email: "system@example.com"},
		To:         []model.Address{{Name: "Owner", Email: account.Email}},
		Subject:    "欢迎使用自托管邮箱",
		Snippet:    "后端 API、SSE、草稿、发件队列和自适应客户端已经准备好。",
		BodyText:   "欢迎使用自托管邮箱。当前演示账号使用 mock connector，接入 Gmail/Outlook/IMAP 凭证后可替换为真实同步。",
		BodyHTML:   "<p>欢迎使用自托管邮箱。</p><p>当前演示账号使用 mock connector，接入 Gmail/Outlook/IMAP 凭证后可替换为真实同步。</p>",
		ReceivedAt: ptrTime(now.Add(-2 * time.Hour)),
		IsRead:     false, Labels: []string{"inbox"}, CreatedAt: now, UpdatedAt: now,
	}
	m.messages["msg_design"] = model.Message{
		ID: "msg_design", AccountID: account.ID, FolderID: inbox.ID, ThreadID: "thr_design", ProviderID: "demo-2",
		From:       model.Address{Name: "Product Notes", Email: "notes@example.com"},
		To:         []model.Address{{Email: account.Email}},
		Subject:    "界面策略",
		Snippet:    "手机单栏、平板双栏、桌面三栏，默认阻止远程图片。",
		BodyText:   "客户端采用 Material 3、自适应布局、低噪声高信息密度界面，支持邮件列表、阅读、搜索、写信和设置。",
		BodyHTML:   "<p>客户端采用 Material 3、自适应布局、低噪声高信息密度界面。</p>",
		ReceivedAt: ptrTime(now.Add(-30 * time.Minute)),
		IsRead:     false, IsStarred: true, Labels: []string{"inbox", "starred"}, CreatedAt: now, UpdatedAt: now,
	}
	m.messages["msg_sent"] = model.Message{
		ID: "msg_sent", AccountID: account.ID, FolderID: sent.ID, ThreadID: "thr_sent", ProviderID: "demo-3",
		From:     model.Address{Name: "Owner", Email: account.Email},
		To:       []model.Address{{Name: "Team", Email: "team@example.com"}},
		Subject:  "项目骨架已完成",
		Snippet:  "后续重点是补齐 Gmail/Graph/IMAP 的真实 provider 调用。",
		BodyText: "项目骨架已完成，后续重点是补齐真实 provider 调用并扩展持久化仓库。",
		SentAt:   ptrTime(now.Add(-10 * time.Minute)),
		IsRead:   true, Labels: []string{"sent"}, CreatedAt: now, UpdatedAt: now,
	}
	m.recountLocked()
}

func (m *Memory) Snapshot() model.MailboxSnapshot {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return model.MailboxSnapshot{
		Accounts: mapValues(m.accounts),
		Folders:  mapValues(m.folders),
		Messages: sortedMessages(mapValues(m.messages)),
		Drafts:   mapValues(m.drafts),
		Rules:    mapValues(m.rules),
		Settings: m.settings,
	}
}

func (m *Memory) ListAccounts() []model.Account {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return mapValues(m.accounts)
}

func (m *Memory) CreateAccount(provider model.Provider, email, displayName string) model.Account {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := time.Now()
	account := model.Account{
		ID:          NewID("acc"),
		Provider:    provider,
		Email:       email,
		DisplayName: displayName,
		Status:      model.AccountNeedsAuth,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	if provider == model.ProviderMock {
		account.Status = model.AccountActive
	}
	m.accounts[account.ID] = account
	for _, folder := range defaultFolders(account.ID) {
		m.folders[folder.ID] = folder
	}
	return account
}

func (m *Memory) GetAccount(id string) (model.Account, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	account, ok := m.accounts[id]
	return account, ok
}

func (m *Memory) UpdateAccount(account model.Account) {
	m.mu.Lock()
	defer m.mu.Unlock()
	account.UpdatedAt = time.Now()
	m.accounts[account.ID] = account
}

func (m *Memory) DeleteAccount(id string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.accounts, id)
	for folderID, folder := range m.folders {
		if folder.AccountID == id {
			delete(m.folders, folderID)
		}
	}
	for msgID, msg := range m.messages {
		if msg.AccountID == id {
			delete(m.messages, msgID)
		}
	}
	m.recountLocked()
}

func (m *Memory) ListFolders(accountID string) []model.Folder {
	m.mu.RLock()
	defer m.mu.RUnlock()
	out := make([]model.Folder, 0)
	for _, folder := range m.folders {
		if accountID == "" || folder.AccountID == accountID {
			out = append(out, folder)
		}
	}
	sort.Slice(out, func(i, j int) bool { return folderRank(out[i].Role) < folderRank(out[j].Role) })
	return out
}

func (m *Memory) GetFolder(id string) (model.Folder, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	folder, ok := m.folders[id]
	return folder, ok
}

func (m *Memory) UpsertFolder(folder model.Folder) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.folders[folder.ID] = folder
	m.recountLocked()
}

type MessageFilter struct {
	AccountID string
	FolderID  string
	Query     string
	Limit     int
}

func (m *Memory) ListMessages(filter MessageFilter) []model.Message {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var out []model.Message
	q := strings.ToLower(strings.TrimSpace(filter.Query))
	for _, msg := range m.messages {
		if filter.AccountID != "" && msg.AccountID != filter.AccountID {
			continue
		}
		if filter.FolderID != "" && msg.FolderID != filter.FolderID {
			continue
		}
		if q != "" && !messageMatches(msg, q) {
			continue
		}
		out = append(out, msg)
	}
	out = sortedMessages(out)
	if filter.Limit > 0 && len(out) > filter.Limit {
		return out[:filter.Limit]
	}
	return out
}

func (m *Memory) GetMessage(id string) (model.Message, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	msg, ok := m.messages[id]
	return msg, ok
}

func (m *Memory) UpsertMessage(msg model.Message) model.Message {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := time.Now()
	if msg.ID == "" {
		msg.ID = NewID("msg")
		msg.CreatedAt = now
	}
	msg.UpdatedAt = now
	msg.HasAttachments = len(msg.Attachments) > 0
	m.messages[msg.ID] = msg
	m.recountLocked()
	return msg
}

func (m *Memory) PatchMessage(id string, read *bool, starred *bool) (model.Message, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	msg, ok := m.messages[id]
	if !ok {
		return model.Message{}, ErrNotFound
	}
	if read != nil {
		msg.IsRead = *read
	}
	if starred != nil {
		msg.IsStarred = *starred
	}
	msg.UpdatedAt = time.Now()
	m.messages[id] = msg
	m.recountLocked()
	return msg, nil
}

func (m *Memory) MoveMessage(id, folderID string) (model.Message, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	msg, ok := m.messages[id]
	if !ok {
		return model.Message{}, ErrNotFound
	}
	if _, ok := m.folders[folderID]; !ok {
		return model.Message{}, ErrNotFound
	}
	msg.FolderID = folderID
	msg.UpdatedAt = time.Now()
	m.messages[id] = msg
	m.recountLocked()
	return msg, nil
}

func (m *Memory) DeleteMessage(id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.messages[id]; !ok {
		return ErrNotFound
	}
	delete(m.messages, id)
	m.recountLocked()
	return nil
}

func (m *Memory) ListDrafts() []model.Draft {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return mapValues(m.drafts)
}

func (m *Memory) SaveDraft(draft model.Draft) model.Draft {
	m.mu.Lock()
	defer m.mu.Unlock()
	if draft.ID == "" {
		draft.ID = NewID("drf")
	}
	draft.UpdatedAt = time.Now()
	m.drafts[draft.ID] = draft
	return draft
}

func (m *Memory) DeleteDraft(id string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.drafts, id)
}

func (m *Memory) EnqueueOutbox(req model.SendRequest) model.OutboxItem {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := time.Now()
	item := model.OutboxItem{ID: NewID("out"), AccountID: req.AccountID, Payload: req, Status: "queued", CreatedAt: now, UpdatedAt: now}
	m.outbox[item.ID] = item
	return item
}

func (m *Memory) PendingOutbox(limit int) []model.OutboxItem {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var out []model.OutboxItem
	for _, item := range m.outbox {
		if item.Status == "queued" || item.Status == "retry" {
			out = append(out, item)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.Before(out[j].CreatedAt) })
	if limit > 0 && len(out) > limit {
		return out[:limit]
	}
	return out
}

func (m *Memory) MarkOutbox(id, status, lastError string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	item, ok := m.outbox[id]
	if !ok {
		return
	}
	item.Status = status
	item.LastError = lastError
	item.Attempts++
	item.UpdatedAt = time.Now()
	m.outbox[id] = item
}

func (m *Memory) ListRules() []model.Rule {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return mapValues(m.rules)
}

func (m *Memory) CreateRule(rule model.Rule) model.Rule {
	m.mu.Lock()
	defer m.mu.Unlock()
	rule.ID = NewID("rule")
	rule.CreatedAt = time.Now()
	m.rules[rule.ID] = rule
	return rule
}

func (m *Memory) DeleteRule(id string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.rules, id)
}

func (m *Memory) Settings() model.Settings {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.settings
}

func (m *Memory) UpdateSettings(settings model.Settings) model.Settings {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.settings = settings
	return m.settings
}

func (m *Memory) recountLocked() {
	for id, folder := range m.folders {
		folder.TotalCount = 0
		folder.UnreadCount = 0
		m.folders[id] = folder
	}
	for _, msg := range m.messages {
		folder, ok := m.folders[msg.FolderID]
		if !ok {
			continue
		}
		folder.TotalCount++
		if !msg.IsRead {
			folder.UnreadCount++
		}
		m.folders[folder.ID] = folder
	}
}

func defaultFolders(accountID string) []model.Folder {
	return []model.Folder{
		{ID: NewID("fld"), AccountID: accountID, ProviderID: "INBOX", Name: "Inbox", Role: "inbox"},
		{ID: NewID("fld"), AccountID: accountID, ProviderID: "SENT", Name: "Sent", Role: "sent"},
		{ID: NewID("fld"), AccountID: accountID, ProviderID: "DRAFTS", Name: "Drafts", Role: "drafts"},
		{ID: NewID("fld"), AccountID: accountID, ProviderID: "ARCHIVE", Name: "Archive", Role: "archive"},
		{ID: NewID("fld"), AccountID: accountID, ProviderID: "TRASH", Name: "Trash", Role: "trash"},
	}
}

func folderRank(role string) int {
	switch role {
	case "inbox":
		return 0
	case "sent":
		return 1
	case "drafts":
		return 2
	case "archive":
		return 3
	case "trash":
		return 4
	default:
		return 100
	}
}

func messageMatches(msg model.Message, q string) bool {
	fields := []string{msg.Subject, msg.Snippet, msg.BodyText, msg.From.Email, msg.From.Name}
	for _, to := range msg.To {
		fields = append(fields, to.Email, to.Name)
	}
	for _, attachment := range msg.Attachments {
		fields = append(fields, attachment.FileName)
	}
	return strings.Contains(strings.ToLower(strings.Join(fields, " ")), q)
}

func sortedMessages(messages []model.Message) []model.Message {
	sort.Slice(messages, func(i, j int) bool {
		left := messageTime(messages[i])
		right := messageTime(messages[j])
		return left.After(right)
	})
	return messages
}

func messageTime(msg model.Message) time.Time {
	if msg.ReceivedAt != nil {
		return *msg.ReceivedAt
	}
	if msg.SentAt != nil {
		return *msg.SentAt
	}
	return msg.UpdatedAt
}

func mapValues[T any](m map[string]T) []T {
	out := make([]T, 0, len(m))
	for _, value := range m {
		out = append(out, value)
	}
	return out
}

func ptrTime(t time.Time) *time.Time {
	return &t
}
