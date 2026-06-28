package store

import (
	"errors"
	"testing"

	"email/backend/internal/model"
)

func TestMoveMessageRejectsFolderFromAnotherAccount(t *testing.T) {
	db := NewMemory()
	accountA := db.CreateAccount(model.Account{
		Provider: model.ProviderMock,
		Email:    "a@example.com",
	})
	accountB := db.CreateAccount(model.Account{
		Provider: model.ProviderMock,
		Email:    "b@example.com",
	})
	inboxA := mustFolderByRole(t, db, accountA.ID, "inbox")
	inboxB := mustFolderByRole(t, db, accountB.ID, "inbox")
	msg := db.UpsertMessage(model.Message{
		AccountID:  accountA.ID,
		FolderID:   inboxA.ID,
		ThreadID:   "thread-a",
		ProviderID: "provider-a",
		From:       model.Address{Email: "sender@example.com"},
		To:         []model.Address{{Email: accountA.Email}},
		Subject:    "Hello",
		Snippet:    "Hello",
		Labels:     []string{"inbox"},
	})

	if _, err := db.MoveMessage(msg.ID, inboxB.ID); !errors.Is(err, ErrInvalidAccountBoundary) {
		t.Fatalf("expected ErrInvalidAccountBoundary, got %v", err)
	}

	got, ok := db.GetMessage(msg.ID)
	if !ok {
		t.Fatal("message disappeared")
	}
	if got.FolderID != inboxA.ID {
		t.Fatalf("message moved across accounts: got folder %q want %q", got.FolderID, inboxA.ID)
	}
}

func TestDeleteAccountRemovesOwnedDataAndRejectsMissing(t *testing.T) {
	db := NewMemory()
	account := db.CreateAccount(model.Account{
		Provider: model.ProviderMock,
		Email:    "owner@example.com",
	})
	inbox := mustFolderByRole(t, db, account.ID, "inbox")
	msg := db.UpsertMessage(model.Message{
		AccountID:  account.ID,
		FolderID:   inbox.ID,
		ThreadID:   "thread-a",
		ProviderID: "provider-a",
		From:       model.Address{Email: "sender@example.com"},
		To:         []model.Address{{Email: account.Email}},
		Subject:    "Hello",
		Snippet:    "Hello",
		Labels:     []string{"inbox"},
	})
	db.SaveDraft(model.Draft{AccountID: account.ID})
	db.EnqueueOutbox(model.SendRequest{
		AccountID: account.ID,
		To:        []model.Address{{Email: "reader@example.com"}},
		Subject:   "Queued",
	})

	if err := db.DeleteAccount(account.ID); err != nil {
		t.Fatalf("delete account failed: %v", err)
	}
	if _, ok := db.GetAccount(account.ID); ok {
		t.Fatal("account still exists")
	}
	if _, ok := db.GetMessage(msg.ID); ok {
		t.Fatal("message still exists")
	}
	if drafts := db.ListDrafts(); len(drafts) != 0 {
		t.Fatalf("drafts were not removed: %#v", drafts)
	}
	if pending := db.PendingOutbox(10); len(pending) != 0 {
		t.Fatalf("outbox items were not removed: %#v", pending)
	}
	if err := db.DeleteAccount(account.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound for missing account, got %v", err)
	}
}

func mustFolderByRole(t *testing.T, db *Memory, accountID string, role string) model.Folder {
	t.Helper()
	for _, folder := range db.ListFolders(accountID) {
		if folder.Role == role {
			return folder
		}
	}
	t.Fatalf("missing %s folder for account %s", role, accountID)
	return model.Folder{}
}
