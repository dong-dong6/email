package store

import (
	"errors"
	"sort"
	"strings"
	"sync"
	"time"

	"email/backend/internal/model"
)

var (
	ErrNotFound               = errors.New("not found")
	ErrInvalidAccountBoundary = errors.New("folder belongs to another account")
)

type Memory struct {
	mu       sync.RWMutex
	accounts map[string]model.Account
	folders  map[string]model.Folder
	messages map[string]model.Message
	drafts   map[string]model.Draft
	outbox   map[string]model.OutboxItem
	rules    map[string]model.Rule
	settings model.Settings
	secrets  *SecretKeeper
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
			RemoteImagesDefault:   false,
			Density:               "comfortable",
			SignatureHTML:         "<p>由自托管邮箱发送。</p>",
			GmailClientID:         "",
			GmailClientSecret:     "",
			MicrosoftClientID:     "",
			MicrosoftClientSecret: "",
		},
		secrets: &SecretKeeper{},
	}
}

func NewMemoryWithKey(key []byte) (*Memory, error) {
	sk, err := NewSecretKeeper(key)
	if err != nil {
		return nil, err
	}
	m := NewMemory()
	m.secrets = sk
	return m, nil
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
	out := make([]model.Account, 0, len(m.accounts))
	for _, a := range m.accounts {
		out = append(out, m.decryptAccount(a))
	}
	return out
}

func (m *Memory) decryptAccount(a model.Account) model.Account {
	a.Password = m.secrets.Decrypt(a.Password)
	return a
}

func (m *Memory) CreateAccount(account model.Account) model.Account {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := time.Now()
	account.ID = NewID("acc")
	if account.DisplayName == "" {
		account.DisplayName = account.Email
	}
	if account.Username == "" {
		account.Username = account.Email
	}
	if account.Status == "" {
		account.Status = model.AccountNeedsAuth
	}
	if account.Provider == model.ProviderMock {
		account.Status = model.AccountActive
	}
	account.Password = m.secrets.Encrypt(account.Password)
	account.CreatedAt = now
	account.UpdatedAt = now
	m.accounts[account.ID] = account
	for _, folder := range defaultFolders(account.ID) {
		m.folders[folder.ID] = folder
	}
	return m.decryptAccount(account)
}

func (m *Memory) GetAccount(id string) (model.Account, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	account, ok := m.accounts[id]
	if !ok {
		return model.Account{}, false
	}
	return m.decryptAccount(account), true
}

func (m *Memory) UpdateAccount(account model.Account) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if account.Password == "" {
		if existing, ok := m.accounts[account.ID]; ok {
			account.Password = existing.Password
		}
	} else {
		account.Password = m.secrets.Encrypt(account.Password)
	}
	account.UpdatedAt = time.Now()
	m.accounts[account.ID] = account
}

func (m *Memory) DeleteAccount(id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.accounts[id]; !ok {
		return ErrNotFound
	}
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
	for draftID, draft := range m.drafts {
		if draft.AccountID == id {
			delete(m.drafts, draftID)
		}
	}
	for outboxID, item := range m.outbox {
		if item.AccountID == id {
			delete(m.outbox, outboxID)
		}
	}
	m.recountLocked()
	return nil
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

func (m *Memory) FindMessageByProvider(accountID, providerID string) (model.Message, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	for _, msg := range m.messages {
		if msg.AccountID == accountID && msg.ProviderID == providerID {
			return msg, true
		}
	}
	return model.Message{}, false
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
	folder, ok := m.folders[folderID]
	if !ok {
		return model.Message{}, ErrNotFound
	}
	if folder.AccountID != msg.AccountID {
		return model.Message{}, ErrInvalidAccountBoundary
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
		{ID: NewID("fld"), AccountID: accountID, ProviderID: "INBOX", Name: "收件箱", Role: "inbox"},
		{ID: NewID("fld"), AccountID: accountID, ProviderID: "SENT", Name: "已发送", Role: "sent"},
		{ID: NewID("fld"), AccountID: accountID, ProviderID: "DRAFTS", Name: "草稿箱", Role: "drafts"},
		{ID: NewID("fld"), AccountID: accountID, ProviderID: "ARCHIVE", Name: "归档", Role: "archive"},
		{ID: NewID("fld"), AccountID: accountID, ProviderID: "TRASH", Name: "已删除", Role: "trash"},
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
