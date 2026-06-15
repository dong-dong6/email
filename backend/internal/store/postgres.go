package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"email/backend/internal/model"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Postgres struct {
	pool *pgxpool.Pool
}

func NewPostgres(ctx context.Context, databaseURL string) (*Postgres, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, fmt.Errorf("create pool: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping: %w", err)
	}
	return &Postgres{pool: pool}, nil
}

func (p *Postgres) Close() {
	p.pool.Close()
}

func (p *Postgres) Snapshot(ctx context.Context) (model.MailboxSnapshot, error) {
	accounts, err := p.ListAccounts(ctx)
	if err != nil {
		return model.MailboxSnapshot{}, err
	}
	folders, err := p.ListFolders(ctx, "")
	if err != nil {
		return model.MailboxSnapshot{}, err
	}
	messages, err := p.ListMessages(ctx, MessageFilter{})
	if err != nil {
		return model.MailboxSnapshot{}, err
	}
	drafts, err := p.ListDrafts(ctx)
	if err != nil {
		return model.MailboxSnapshot{}, err
	}
	rules, err := p.ListRules(ctx)
	if err != nil {
		return model.MailboxSnapshot{}, err
	}
	settings, err := p.Settings(ctx)
	if err != nil {
		return model.MailboxSnapshot{}, err
	}
	return model.MailboxSnapshot{
		Accounts: accounts,
		Folders:  folders,
		Messages: messages,
		Drafts:   drafts,
		Rules:    rules,
		Settings: settings,
	}, nil
}

func (p *Postgres) ListAccounts(ctx context.Context) ([]model.Account, error) {
	rows, err := p.pool.Query(ctx, `
		SELECT id, provider, email, display_name, username, password_secret,
		       imap_host, imap_port, imap_tls, smtp_host, smtp_port, smtp_tls,
		       status, sync_cursor, last_error, created_at, updated_at
		FROM accounts ORDER BY created_at
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var accounts []model.Account
	for rows.Next() {
		var a model.Account
		err := rows.Scan(&a.ID, &a.Provider, &a.Email, &a.DisplayName, &a.Username, &a.Password,
			&a.IMAPHost, &a.IMAPPort, &a.IMAPTLS, &a.SMTPHost, &a.SMTPPort, &a.SMTPTLS,
			&a.Status, &a.SyncCursor, &a.LastError, &a.CreatedAt, &a.UpdatedAt)
		if err != nil {
			return nil, err
		}
		accounts = append(accounts, a)
	}
	return accounts, rows.Err()
}

func (p *Postgres) CreateAccount(ctx context.Context, account model.Account) (model.Account, error) {
	if account.ID == "" {
		account.ID = NewID("acc")
	}
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
	now := time.Now()
	account.CreatedAt = now
	account.UpdatedAt = now
	_, err := p.pool.Exec(ctx, `
		INSERT INTO accounts (id, provider, email, display_name, username, password_secret,
		       imap_host, imap_port, imap_tls, smtp_host, smtp_port, smtp_tls,
		       status, sync_cursor, last_error, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
	`, account.ID, account.Provider, account.Email, account.DisplayName, account.Username, account.Password,
		account.IMAPHost, account.IMAPPort, account.IMAPTLS, account.SMTPHost, account.SMTPPort, account.SMTPTLS,
		account.Status, account.SyncCursor, account.LastError, account.CreatedAt, account.UpdatedAt)
	if err != nil {
		return model.Account{}, err
	}
	for _, folder := range defaultFolders(account.ID) {
		_, err = p.pool.Exec(ctx, `
			INSERT INTO folders (id, account_id, provider_id, name, role)
			VALUES ($1, $2, $3, $4, $5)
		`, folder.ID, folder.AccountID, folder.ProviderID, folder.Name, folder.Role)
		if err != nil {
			return model.Account{}, err
		}
	}
	return account, nil
}

func (p *Postgres) GetAccount(ctx context.Context, id string) (model.Account, bool) {
	var a model.Account
	err := p.pool.QueryRow(ctx, `
		SELECT id, provider, email, display_name, username, password_secret,
		       imap_host, imap_port, imap_tls, smtp_host, smtp_port, smtp_tls,
		       status, sync_cursor, last_error, created_at, updated_at
		FROM accounts WHERE id = $1
	`, id).Scan(&a.ID, &a.Provider, &a.Email, &a.DisplayName, &a.Username, &a.Password,
		&a.IMAPHost, &a.IMAPPort, &a.IMAPTLS, &a.SMTPHost, &a.SMTPPort, &a.SMTPTLS,
		&a.Status, &a.SyncCursor, &a.LastError, &a.CreatedAt, &a.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return model.Account{}, false
	}
	return a, err == nil
}

func (p *Postgres) UpdateAccount(ctx context.Context, account model.Account) error {
	account.UpdatedAt = time.Now()
	_, err := p.pool.Exec(ctx, `
		UPDATE accounts SET provider=$2, email=$3, display_name=$4, username=$5, password_secret=$6,
		       imap_host=$7, imap_port=$8, imap_tls=$9, smtp_host=$10, smtp_port=$11, smtp_tls=$12,
		       status=$13, sync_cursor=$14, last_error=$15, updated_at=$16
		WHERE id = $1
	`, account.ID, account.Provider, account.Email, account.DisplayName, account.Username, account.Password,
		account.IMAPHost, account.IMAPPort, account.IMAPTLS, account.SMTPHost, account.SMTPPort, account.SMTPTLS,
		account.Status, account.SyncCursor, account.LastError, account.UpdatedAt)
	return err
}

func (p *Postgres) DeleteAccount(ctx context.Context, id string) error {
	_, err := p.pool.Exec(ctx, "DELETE FROM accounts WHERE id = $1", id)
	return err
}

func (p *Postgres) ListFolders(ctx context.Context, accountID string) ([]model.Folder, error) {
	query := "SELECT id, account_id, provider_id, name, role, unread_count, total_count FROM folders"
	args := []any{}
	if accountID != "" {
		query += " WHERE account_id = $1"
		args = append(args, accountID)
	}
	query += " ORDER BY CASE role WHEN 'inbox' THEN 0 WHEN 'sent' THEN 1 WHEN 'drafts' THEN 2 WHEN 'archive' THEN 3 WHEN 'trash' THEN 4 ELSE 100 END"
	rows, err := p.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var folders []model.Folder
	for rows.Next() {
		var f model.Folder
		if err := rows.Scan(&f.ID, &f.AccountID, &f.ProviderID, &f.Name, &f.Role, &f.UnreadCount, &f.TotalCount); err != nil {
			return nil, err
		}
		folders = append(folders, f)
	}
	return folders, rows.Err()
}

func (p *Postgres) UpsertFolder(ctx context.Context, folder model.Folder) error {
	_, err := p.pool.Exec(ctx, `
		INSERT INTO folders (id, account_id, provider_id, name, role, unread_count, total_count)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (id) DO UPDATE SET unread_count=$6, total_count=$7
	`, folder.ID, folder.AccountID, folder.ProviderID, folder.Name, folder.Role, folder.UnreadCount, folder.TotalCount)
	return err
}

func (p *Postgres) ListMessages(ctx context.Context, filter MessageFilter) ([]model.Message, error) {
	query := `SELECT id, account_id, folder_id, thread_id, provider_id, sender, recipients,
	           subject, snippet, body_text_ref, body_html_ref, received_at, sent_at,
	           is_read, is_starred, labels, created_at, updated_at FROM messages WHERE 1=1`
	args := []any{}
	argIdx := 1
	if filter.AccountID != "" {
		query += fmt.Sprintf(" AND account_id = $%d", argIdx)
		args = append(args, filter.AccountID)
		argIdx++
	}
	if filter.FolderID != "" {
		query += fmt.Sprintf(" AND folder_id = $%d", argIdx)
		args = append(args, filter.FolderID)
		argIdx++
	}
	if filter.Query != "" {
		query += fmt.Sprintf(" AND search_text @@ plainto_tsquery($%d)", argIdx)
		args = append(args, filter.Query)
		argIdx++
	}
	query += " ORDER BY COALESCE(received_at, sent_at, updated_at) DESC"
	if filter.Limit > 0 {
		query += fmt.Sprintf(" LIMIT $%d", argIdx)
		args = append(args, filter.Limit)
	}
	rows, err := p.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var messages []model.Message
	for rows.Next() {
		var m model.Message
		var fromJSON, toJSON []byte
		var labels []string
		if err := rows.Scan(&m.ID, &m.AccountID, &m.FolderID, &m.ThreadID, &m.ProviderID,
			&fromJSON, &toJSON, &m.Subject, &m.Snippet, &m.BodyText, &m.BodyHTML,
			&m.ReceivedAt, &m.SentAt, &m.IsRead, &m.IsStarred, &labels, &m.CreatedAt, &m.UpdatedAt); err != nil {
			return nil, err
		}
		_ = json.Unmarshal(fromJSON, &m.From)
		_ = json.Unmarshal(toJSON, &m.To)
		m.Labels = labels
		messages = append(messages, m)
	}
	return messages, rows.Err()
}

func (p *Postgres) GetMessage(ctx context.Context, id string) (model.Message, bool) {
	var m model.Message
	var fromJSON, toJSON []byte
	var labels []string
	err := p.pool.QueryRow(ctx, `
		SELECT id, account_id, folder_id, thread_id, provider_id, sender, recipients,
		       subject, snippet, body_text_ref, body_html_ref, received_at, sent_at,
		       is_read, is_starred, labels, created_at, updated_at
		FROM messages WHERE id = $1
	`, id).Scan(&m.ID, &m.AccountID, &m.FolderID, &m.ThreadID, &m.ProviderID,
		&fromJSON, &toJSON, &m.Subject, &m.Snippet, &m.BodyText, &m.BodyHTML,
		&m.ReceivedAt, &m.SentAt, &m.IsRead, &m.IsStarred, &labels, &m.CreatedAt, &m.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return model.Message{}, false
	}
	_ = json.Unmarshal(fromJSON, &m.From)
	_ = json.Unmarshal(toJSON, &m.To)
	m.Labels = labels
	return m, err == nil
}

func (p *Postgres) FindMessageByProvider(ctx context.Context, accountID, providerID string) (model.Message, bool) {
	var m model.Message
	var fromJSON, toJSON []byte
	var labels []string
	err := p.pool.QueryRow(ctx, `
		SELECT id, account_id, folder_id, thread_id, provider_id, sender, recipients,
		       subject, snippet, body_text_ref, body_html_ref, received_at, sent_at,
		       is_read, is_starred, labels, created_at, updated_at
		FROM messages WHERE account_id = $1 AND provider_id = $2
	`, accountID, providerID).Scan(&m.ID, &m.AccountID, &m.FolderID, &m.ThreadID, &m.ProviderID,
		&fromJSON, &toJSON, &m.Subject, &m.Snippet, &m.BodyText, &m.BodyHTML,
		&m.ReceivedAt, &m.SentAt, &m.IsRead, &m.IsStarred, &labels, &m.CreatedAt, &m.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return model.Message{}, false
	}
	_ = json.Unmarshal(fromJSON, &m.From)
	_ = json.Unmarshal(toJSON, &m.To)
	m.Labels = labels
	return m, err == nil
}

func (p *Postgres) UpsertMessage(ctx context.Context, msg model.Message) (model.Message, error) {
	now := time.Now()
	if msg.ID == "" {
		msg.ID = NewID("msg")
		msg.CreatedAt = now
	}
	msg.UpdatedAt = now
	msg.HasAttachments = len(msg.Attachments) > 0
	fromJSON, _ := json.Marshal(msg.From)
	toJSON, _ := json.Marshal(msg.To)
	_, err := p.pool.Exec(ctx, `
		INSERT INTO messages (id, account_id, folder_id, thread_id, provider_id, sender, recipients,
		       subject, snippet, body_text_ref, body_html_ref, received_at, sent_at,
		       is_read, is_starred, labels, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
		ON CONFLICT (id) DO UPDATE SET sender=$6, recipients=$7, subject=$8, snippet=$9,
		       body_text_ref=$10, body_html_ref=$11, received_at=$12, sent_at=$13,
		       is_read=$14, is_starred=$15, labels=$16, updated_at=$18
	`, msg.ID, msg.AccountID, msg.FolderID, msg.ThreadID, msg.ProviderID,
		fromJSON, toJSON, msg.Subject, msg.Snippet, msg.BodyText, msg.BodyHTML,
		msg.ReceivedAt, msg.SentAt, msg.IsRead, msg.IsStarred, msg.Labels, msg.CreatedAt, msg.UpdatedAt)
	if err != nil {
		return model.Message{}, err
	}
	return msg, nil
}

func (p *Postgres) PatchMessage(ctx context.Context, id string, read *bool, starred *bool) (model.Message, error) {
	msg, ok := p.GetMessage(ctx, id)
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
	_, err := p.pool.Exec(ctx, "UPDATE messages SET is_read=$2, is_starred=$3, updated_at=$4 WHERE id=$1",
		id, msg.IsRead, msg.IsStarred, msg.UpdatedAt)
	return msg, err
}

func (p *Postgres) MoveMessage(ctx context.Context, id, folderID string) (model.Message, error) {
	msg, ok := p.GetMessage(ctx, id)
	if !ok {
		return model.Message{}, ErrNotFound
	}
	msg.FolderID = folderID
	msg.UpdatedAt = time.Now()
	_, err := p.pool.Exec(ctx, "UPDATE messages SET folder_id=$2, updated_at=$3 WHERE id=$1",
		id, folderID, msg.UpdatedAt)
	return msg, err
}

func (p *Postgres) DeleteMessage(ctx context.Context, id string) error {
	tag, err := p.pool.Exec(ctx, "DELETE FROM messages WHERE id=$1", id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (p *Postgres) ListDrafts(ctx context.Context) ([]model.Draft, error) {
	rows, err := p.pool.Query(ctx, "SELECT id, account_id, thread_id, payload, updated_at FROM drafts ORDER BY updated_at DESC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var drafts []model.Draft
	for rows.Next() {
		var d model.Draft
		var payload []byte
		if err := rows.Scan(&d.ID, &d.AccountID, &d.ThreadID, &payload, &d.UpdatedAt); err != nil {
			return nil, err
		}
		_ = json.Unmarshal(payload, &d.Payload)
		drafts = append(drafts, d)
	}
	return drafts, rows.Err()
}

func (p *Postgres) SaveDraft(ctx context.Context, draft model.Draft) (model.Draft, error) {
	if draft.ID == "" {
		draft.ID = NewID("drf")
	}
	draft.UpdatedAt = time.Now()
	payload, _ := json.Marshal(draft.Payload)
	_, err := p.pool.Exec(ctx, `
		INSERT INTO drafts (id, account_id, thread_id, payload, updated_at)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (id) DO UPDATE SET payload=$4, updated_at=$5
	`, draft.ID, draft.AccountID, draft.ThreadID, payload, draft.UpdatedAt)
	return draft, err
}

func (p *Postgres) DeleteDraft(ctx context.Context, id string) error {
	_, err := p.pool.Exec(ctx, "DELETE FROM drafts WHERE id=$1", id)
	return err
}

func (p *Postgres) EnqueueOutbox(ctx context.Context, req model.SendRequest) (model.OutboxItem, error) {
	now := time.Now()
	item := model.OutboxItem{ID: NewID("out"), AccountID: req.AccountID, Payload: req, Status: "queued", CreatedAt: now, UpdatedAt: now}
	payload, _ := json.Marshal(item.Payload)
	_, err := p.pool.Exec(ctx, `
		INSERT INTO outbox (id, account_id, payload, status, attempts, last_error, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`, item.ID, item.AccountID, payload, item.Status, item.Attempts, item.LastError, item.CreatedAt, item.UpdatedAt)
	return item, err
}

func (p *Postgres) PendingOutbox(ctx context.Context, limit int) ([]model.OutboxItem, error) {
	query := "SELECT id, account_id, payload, status, attempts, last_error, created_at, updated_at FROM outbox WHERE status IN ('queued', 'retry') ORDER BY created_at"
	if limit > 0 {
		query += fmt.Sprintf(" LIMIT %d", limit)
	}
	rows, err := p.pool.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var items []model.OutboxItem
	for rows.Next() {
		var item model.OutboxItem
		var payload []byte
		if err := rows.Scan(&item.ID, &item.AccountID, &payload, &item.Status, &item.Attempts, &item.LastError, &item.CreatedAt, &item.UpdatedAt); err != nil {
			return nil, err
		}
		_ = json.Unmarshal(payload, &item.Payload)
		items = append(items, item)
	}
	return items, rows.Err()
}

func (p *Postgres) MarkOutbox(ctx context.Context, id, status, lastError string) error {
	_, err := p.pool.Exec(ctx, `
		UPDATE outbox SET status=$2, last_error=$3, attempts=attempts+1, updated_at=$4 WHERE id=$1
	`, id, status, lastError, time.Now())
	return err
}

func (p *Postgres) ListRules(ctx context.Context) ([]model.Rule, error) {
	rows, err := p.pool.Query(ctx, "SELECT id, name, enabled, query, action, target, created_at FROM rules ORDER BY created_at")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var rules []model.Rule
	for rows.Next() {
		var r model.Rule
		if err := rows.Scan(&r.ID, &r.Name, &r.Enabled, &r.Query, &r.Action, &r.Target, &r.CreatedAt); err != nil {
			return nil, err
		}
		rules = append(rules, r)
	}
	return rules, rows.Err()
}

func (p *Postgres) CreateRule(ctx context.Context, rule model.Rule) (model.Rule, error) {
	rule.ID = NewID("rule")
	rule.CreatedAt = time.Now()
	_, err := p.pool.Exec(ctx, `
		INSERT INTO rules (id, name, enabled, query, action, target, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, rule.ID, rule.Name, rule.Enabled, rule.Query, rule.Action, rule.Target, rule.CreatedAt)
	return rule, err
}

func (p *Postgres) DeleteRule(ctx context.Context, id string) error {
	_, err := p.pool.Exec(ctx, "DELETE FROM rules WHERE id=$1", id)
	return err
}

func (p *Postgres) Settings(ctx context.Context) (model.Settings, error) {
	var s model.Settings
	err := p.pool.QueryRow(ctx, "SELECT remote_images_default, density, signature_html, gmail_client_id, gmail_client_secret, microsoft_client_id, microsoft_client_secret FROM settings WHERE id = TRUE").Scan(
		&s.RemoteImagesDefault, &s.Density, &s.SignatureHTML, &s.GmailClientID, &s.GmailClientSecret, &s.MicrosoftClientID, &s.MicrosoftClientSecret)
	if errors.Is(err, pgx.ErrNoRows) {
		return model.Settings{
			RemoteImagesDefault:   false,
			Density:               "comfortable",
			SignatureHTML:         "<p>由自托管邮箱发送。</p>",
			GmailClientID:         "",
			GmailClientSecret:     "",
			MicrosoftClientID:     "",
			MicrosoftClientSecret: "",
		}, nil
	}
	return s, err
}

func (p *Postgres) UpdateSettings(ctx context.Context, settings model.Settings) (model.Settings, error) {
	_, err := p.pool.Exec(ctx, `
		INSERT INTO settings (id, remote_images_default, density, signature_html, gmail_client_id, gmail_client_secret, microsoft_client_id, microsoft_client_secret)
		VALUES (TRUE, $1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (id) DO UPDATE SET remote_images_default=$1, density=$2, signature_html=$3, gmail_client_id=$4, gmail_client_secret=$5, microsoft_client_id=$6, microsoft_client_secret=$7
	`, settings.RemoteImagesDefault, settings.Density, settings.SignatureHTML, settings.GmailClientID, settings.GmailClientSecret, settings.MicrosoftClientID, settings.MicrosoftClientSecret)
	return settings, err
}

func (p *Postgres) RecountFolders(ctx context.Context) error {
	_, err := p.pool.Exec(ctx, `
		UPDATE folders f SET
			total_count = (SELECT COUNT(*) FROM messages m WHERE m.folder_id = f.id),
			unread_count = (SELECT COUNT(*) FROM messages m WHERE m.folder_id = f.id AND NOT m.is_read)
	`)
	return err
}

func (p *Postgres) CreateUser(ctx context.Context, email, passwordHash, role string) (string, error) {
	id := NewID("usr")
	_, err := p.pool.Exec(ctx, `
		INSERT INTO users (id, email, password_hash, role, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, id, strings.ToLower(email), passwordHash, role, time.Now(), time.Now())
	return id, err
}

func (p *Postgres) GetUserByEmail(ctx context.Context, email string) (id, passwordHash, role string, err error) {
	err = p.pool.QueryRow(ctx, "SELECT id, password_hash, role FROM users WHERE email=$1", strings.ToLower(email)).Scan(&id, &passwordHash, &role)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", "", "", ErrNotFound
	}
	return
}

func (p *Postgres) HasUsers(ctx context.Context) (bool, error) {
	var count int
	err := p.pool.QueryRow(ctx, "SELECT COUNT(*) FROM users").Scan(&count)
	return count > 0, err
}
