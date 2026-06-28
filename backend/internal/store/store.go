package store

import (
	"context"

	"email/backend/internal/model"
)

type MailStore interface {
	Snapshot(ctx context.Context) (model.MailboxSnapshot, error)
	ListAccounts(ctx context.Context) ([]model.Account, error)
	CreateAccount(ctx context.Context, account model.Account) (model.Account, error)
	GetAccount(ctx context.Context, id string) (model.Account, bool, error)
	UpdateAccount(ctx context.Context, account model.Account) error
	DeleteAccount(ctx context.Context, id string) error
	ListFolders(ctx context.Context, accountID string) ([]model.Folder, error)
	GetFolder(ctx context.Context, id string) (model.Folder, bool, error)
	UpsertFolder(ctx context.Context, folder model.Folder) error
	ListMessages(ctx context.Context, filter MessageFilter) ([]model.Message, error)
	GetMessage(ctx context.Context, id string) (model.Message, bool, error)
	FindMessageByProvider(ctx context.Context, accountID, providerID string) (model.Message, bool, error)
	UpsertMessage(ctx context.Context, msg model.Message) (model.Message, error)
	PatchMessage(ctx context.Context, id string, read *bool, starred *bool) (model.Message, error)
	MoveMessage(ctx context.Context, id, folderID string) (model.Message, error)
	DeleteMessage(ctx context.Context, id string) error
	ListDrafts(ctx context.Context) ([]model.Draft, error)
	SaveDraft(ctx context.Context, draft model.Draft) (model.Draft, error)
	DeleteDraft(ctx context.Context, id string) error
	EnqueueOutbox(ctx context.Context, req model.SendRequest) (model.OutboxItem, error)
	PendingOutbox(ctx context.Context, limit int) ([]model.OutboxItem, error)
	MarkOutbox(ctx context.Context, id, status, lastError string) (model.OutboxItem, error)
	ListRules(ctx context.Context) ([]model.Rule, error)
	CreateRule(ctx context.Context, rule model.Rule) (model.Rule, error)
	DeleteRule(ctx context.Context, id string) error
	Settings(ctx context.Context) (model.Settings, error)
	UpdateSettings(ctx context.Context, settings model.Settings) (model.Settings, error)
}
