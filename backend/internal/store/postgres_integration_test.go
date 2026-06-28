package store

import (
	"context"
	"os"
	"testing"
	"time"

	"email/backend/internal/model"
)

func TestPostgresMailStorePersistsMailboxState(t *testing.T) {
	databaseURL := os.Getenv("TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	ctx := context.Background()
	key := []byte("0123456789abcdef0123456789abcdef")

	pg, err := NewPostgres(ctx, databaseURL, key)
	if err != nil {
		t.Fatal(err)
	}
	account, err := pg.CreateAccount(ctx, model.Account{
		Provider:    model.ProviderIMAP,
		Email:       "persist@example.com",
		DisplayName: "Persist Test",
		Username:    "persist@example.com",
		Password:    "account-secret",
		IMAPHost:    "imap.example.com",
		IMAPPort:    993,
		SMTPHost:    "smtp.example.com",
		SMTPPort:    587,
		Status:      model.AccountActive,
	})
	if err != nil {
		t.Fatal(err)
	}
	folders, err := pg.ListFolders(ctx, account.ID)
	if err != nil {
		t.Fatal(err)
	}
	var inbox model.Folder
	for _, folder := range folders {
		if folder.Role == "inbox" {
			inbox = folder
			break
		}
	}
	if inbox.ID == "" {
		t.Fatal("missing inbox folder")
	}
	receivedAt := time.Now().UTC().Truncate(time.Second)
	msg, err := pg.UpsertMessage(ctx, model.Message{
		AccountID:  account.ID,
		FolderID:   inbox.ID,
		ThreadID:   "thread-persist",
		ProviderID: "provider-persist",
		From:       model.Address{Name: "Sender", Email: "sender@example.com"},
		To:         []model.Address{{Email: "to@example.com"}},
		Cc:         []model.Address{{Email: "cc@example.com"}},
		Bcc:        []model.Address{{Email: "bcc@example.com"}},
		Subject:    "Persisted message",
		Snippet:    "Persisted snippet",
		BodyText:   "Persisted body",
		ReceivedAt: &receivedAt,
		Labels:     []string{"inbox"},
		Attachments: []model.Attachment{{
			ID:          NewID("att"),
			FileName:    "invoice.pdf",
			ContentType: "application/pdf",
			Size:        123,
			BlobID:      "blob-persist",
		}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pg.UpdateSettings(ctx, model.Settings{
		Density:               "compact",
		SignatureHTML:         "<p>persist</p>",
		GmailClientID:         "gmail-client",
		GmailClientSecret:     "gmail-secret",
		MicrosoftClientID:     "ms-client",
		MicrosoftClientSecret: "ms-secret",
	}); err != nil {
		t.Fatal(err)
	}
	item, err := pg.EnqueueOutbox(ctx, model.SendRequest{
		AccountID: account.ID,
		To:        []model.Address{{Email: "reader@example.com"}},
		Subject:   "Queued",
		BodyText:  "Queued body",
	})
	if err != nil {
		t.Fatal(err)
	}
	pg.Close()

	reopened, err := NewPostgres(ctx, databaseURL, key)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	snapshot, err := reopened.Snapshot(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if !containsAccount(snapshot.Accounts, account.ID) {
		t.Fatalf("account %s was not persisted", account.ID)
	}
	persisted, ok, err := reopened.GetMessage(ctx, msg.ID)
	if err != nil {
		t.Fatal(err)
	}
	if !ok {
		t.Fatalf("message %s was not persisted", msg.ID)
	}
	if len(persisted.Cc) != 1 || persisted.Cc[0].Email != "cc@example.com" {
		t.Fatalf("cc recipients were not persisted: %#v", persisted.Cc)
	}
	if len(persisted.Bcc) != 1 || persisted.Bcc[0].Email != "bcc@example.com" {
		t.Fatalf("bcc recipients were not persisted: %#v", persisted.Bcc)
	}
	if len(persisted.Attachments) != 1 || persisted.Attachments[0].BlobID != "blob-persist" {
		t.Fatalf("attachments were not persisted: %#v", persisted.Attachments)
	}
	settings, err := reopened.Settings(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if settings.GmailClientSecret != "gmail-secret" || settings.MicrosoftClientSecret != "ms-secret" {
		t.Fatalf("settings secrets were not restored: %#v", settings)
	}
	pending, err := reopened.PendingOutbox(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	if !containsOutboxItem(pending, item.ID) {
		t.Fatalf("outbox item %s was not persisted: %#v", item.ID, pending)
	}
}

func containsAccount(accounts []model.Account, id string) bool {
	for _, account := range accounts {
		if account.ID == id {
			return true
		}
	}
	return false
}

func containsOutboxItem(items []model.OutboxItem, id string) bool {
	for _, item := range items {
		if item.ID == id {
			return true
		}
	}
	return false
}
