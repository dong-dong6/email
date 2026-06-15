package model

import "time"

type Provider string

const (
	ProviderMock    Provider = "mock"
	ProviderGmail   Provider = "gmail"
	ProviderOutlook Provider = "outlook"
	ProviderIMAP    Provider = "imap"
)

type AccountStatus string

const (
	AccountActive      AccountStatus = "active"
	AccountNeedsAuth   AccountStatus = "needs_auth"
	AccountSyncing     AccountStatus = "syncing"
	AccountError       AccountStatus = "error"
	AccountUnavailable AccountStatus = "unavailable"
)

type Address struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

type Account struct {
	ID          string        `json:"id"`
	Provider    Provider      `json:"provider"`
	Email       string        `json:"email"`
	DisplayName string        `json:"display_name"`
	Username    string        `json:"username,omitempty"`
	Password    string        `json:"-"`
	IMAPHost    string        `json:"imap_host,omitempty"`
	IMAPPort    int           `json:"imap_port,omitempty"`
	IMAPTLS     bool          `json:"imap_tls"`
	SMTPHost    string        `json:"smtp_host,omitempty"`
	SMTPPort    int           `json:"smtp_port,omitempty"`
	SMTPTLS     bool          `json:"smtp_tls"`
	Status      AccountStatus `json:"status"`
	SyncCursor  string        `json:"sync_cursor"`
	LastError   string        `json:"last_error,omitempty"`
	CreatedAt   time.Time     `json:"created_at"`
	UpdatedAt   time.Time     `json:"updated_at"`
}

type Folder struct {
	ID          string `json:"id"`
	AccountID   string `json:"account_id"`
	ProviderID  string `json:"provider_id"`
	Name        string `json:"name"`
	Role        string `json:"role"`
	UnreadCount int    `json:"unread_count"`
	TotalCount  int    `json:"total_count"`
}

type Attachment struct {
	ID          string `json:"id"`
	MessageID   string `json:"message_id"`
	FileName    string `json:"file_name"`
	ContentType string `json:"content_type"`
	Size        int64  `json:"size"`
	BlobID      string `json:"blob_id"`
	Inline      bool   `json:"inline"`
	ContentID   string `json:"content_id,omitempty"`
}

type Message struct {
	ID             string       `json:"id"`
	AccountID      string       `json:"account_id"`
	FolderID       string       `json:"folder_id"`
	ThreadID       string       `json:"thread_id"`
	ProviderID     string       `json:"provider_id"`
	From           Address      `json:"from"`
	To             []Address    `json:"to"`
	Cc             []Address    `json:"cc,omitempty"`
	Bcc            []Address    `json:"bcc,omitempty"`
	Subject        string       `json:"subject"`
	Snippet        string       `json:"snippet"`
	BodyText       string       `json:"body_text,omitempty"`
	BodyHTML       string       `json:"body_html,omitempty"`
	ReceivedAt     *time.Time   `json:"received_at,omitempty"`
	SentAt         *time.Time   `json:"sent_at,omitempty"`
	IsRead         bool         `json:"is_read"`
	IsStarred      bool         `json:"is_starred"`
	Labels         []string     `json:"labels"`
	HasAttachments bool         `json:"has_attachments"`
	Attachments    []Attachment `json:"attachments,omitempty"`
	CreatedAt      time.Time    `json:"created_at"`
	UpdatedAt      time.Time    `json:"updated_at"`
}

type Draft struct {
	ID        string      `json:"id"`
	AccountID string      `json:"account_id"`
	ThreadID  string      `json:"thread_id,omitempty"`
	Payload   SendRequest `json:"payload"`
	UpdatedAt time.Time   `json:"updated_at"`
}

type SendRequest struct {
	AccountID      string       `json:"account_id"`
	ThreadID       string       `json:"thread_id,omitempty"`
	From           *Address     `json:"from,omitempty"`
	To             []Address    `json:"to"`
	Cc             []Address    `json:"cc,omitempty"`
	Bcc            []Address    `json:"bcc,omitempty"`
	Subject        string       `json:"subject"`
	BodyText       string       `json:"body_text,omitempty"`
	BodyHTML       string       `json:"body_html,omitempty"`
	ReplyToID      string       `json:"reply_to_id,omitempty"`
	ForwardFromID  string       `json:"forward_from_id,omitempty"`
	Attachments    []Attachment `json:"attachments,omitempty"`
	IdempotencyKey string       `json:"idempotency_key,omitempty"`
}

type OutboxItem struct {
	ID        string      `json:"id"`
	AccountID string      `json:"account_id"`
	Payload   SendRequest `json:"payload"`
	Status    string      `json:"status"`
	Attempts  int         `json:"attempts"`
	LastError string      `json:"last_error,omitempty"`
	CreatedAt time.Time   `json:"created_at"`
	UpdatedAt time.Time   `json:"updated_at"`
}

type Rule struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Enabled   bool      `json:"enabled"`
	Query     string    `json:"query"`
	Action    string    `json:"action"`
	Target    string    `json:"target"`
	CreatedAt time.Time `json:"created_at"`
}

type Settings struct {
	RemoteImagesDefault bool     `json:"remote_images_default"`
	Density             string   `json:"density"`
	SignatureHTML       string   `json:"signature_html"`
	GmailClientID       string   `json:"gmail_client_id,omitempty"`
	MicrosoftClientID   string   `json:"microsoft_client_id,omitempty"`
	AllowedOrigins      []string `json:"allowed_origins"`
}

type Event struct {
	Type      string    `json:"type"`
	AccountID string    `json:"account_id,omitempty"`
	MessageID string    `json:"message_id,omitempty"`
	Payload   any       `json:"payload,omitempty"`
	At        time.Time `json:"at"`
}

type MailboxSnapshot struct {
	Accounts []Account `json:"accounts"`
	Folders  []Folder  `json:"folders"`
	Messages []Message `json:"messages"`
	Drafts   []Draft   `json:"drafts"`
	Rules    []Rule    `json:"rules"`
	Settings Settings  `json:"settings"`
}
