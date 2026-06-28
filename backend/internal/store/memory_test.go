package store

import (
	"context"
	"errors"
	"testing"

	"email/backend/internal/model"
)

func TestMoveMessageRejectsFolderFromAnotherAccount(t *testing.T) {
	ctx := context.Background()
	db := NewMemory()
	accountA, err := db.CreateAccount(ctx, model.Account{
		Provider: model.ProviderMock,
		Email:    "a@example.com",
	})
	if err != nil {
		t.Fatal(err)
	}
	accountB, err := db.CreateAccount(ctx, model.Account{
		Provider: model.ProviderMock,
		Email:    "b@example.com",
	})
	if err != nil {
		t.Fatal(err)
	}
	inboxA := mustFolderByRole(t, db, accountA.ID, "inbox")
	inboxB := mustFolderByRole(t, db, accountB.ID, "inbox")
	msg, err := db.UpsertMessage(ctx, model.Message{
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
	if err != nil {
		t.Fatal(err)
	}

	if _, err := db.MoveMessage(ctx, msg.ID, inboxB.ID); !errors.Is(err, ErrInvalidAccountBoundary) {
		t.Fatalf("expected ErrInvalidAccountBoundary, got %v", err)
	}

	got, ok, err := db.GetMessage(ctx, msg.ID)
	if err != nil {
		t.Fatal(err)
	}
	if !ok {
		t.Fatal("message disappeared")
	}
	if got.FolderID != inboxA.ID {
		t.Fatalf("message moved across accounts: got folder %q want %q", got.FolderID, inboxA.ID)
	}
}

func TestDeleteAccountRemovesOwnedDataAndRejectsMissing(t *testing.T) {
	ctx := context.Background()
	db := NewMemory()
	account, err := db.CreateAccount(ctx, model.Account{
		Provider: model.ProviderMock,
		Email:    "owner@example.com",
	})
	if err != nil {
		t.Fatal(err)
	}
	inbox := mustFolderByRole(t, db, account.ID, "inbox")
	msg, err := db.UpsertMessage(ctx, model.Message{
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
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.SaveDraft(ctx, model.Draft{AccountID: account.ID}); err != nil {
		t.Fatal(err)
	}
	if _, err := db.EnqueueOutbox(ctx, model.SendRequest{
		AccountID: account.ID,
		To:        []model.Address{{Email: "reader@example.com"}},
		Subject:   "Queued",
	}); err != nil {
		t.Fatal(err)
	}

	if err := db.DeleteAccount(ctx, account.ID); err != nil {
		t.Fatalf("delete account failed: %v", err)
	}
	if _, ok, err := db.GetAccount(ctx, account.ID); err != nil {
		t.Fatal(err)
	} else if ok {
		t.Fatal("account still exists")
	}
	if _, ok, err := db.GetMessage(ctx, msg.ID); err != nil {
		t.Fatal(err)
	} else if ok {
		t.Fatal("message still exists")
	}
	if drafts, err := db.ListDrafts(ctx); err != nil {
		t.Fatal(err)
	} else if len(drafts) != 0 {
		t.Fatalf("drafts were not removed: %#v", drafts)
	}
	if pending, err := db.PendingOutbox(ctx, 10); err != nil {
		t.Fatal(err)
	} else if len(pending) != 0 {
		t.Fatalf("outbox items were not removed: %#v", pending)
	}
	if err := db.DeleteAccount(ctx, account.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound for missing account, got %v", err)
	}
}

func mustFolderByRole(t *testing.T, db *Memory, accountID string, role string) model.Folder {
	t.Helper()
	folders, err := db.ListFolders(context.Background(), accountID)
	if err != nil {
		t.Fatal(err)
	}
	for _, folder := range folders {
		if folder.Role == role {
			return folder
		}
	}
	t.Fatalf("missing %s folder for account %s", role, accountID)
	return model.Folder{}
}
