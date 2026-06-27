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
