package mail

import (
	"context"
	"errors"
	"testing"

	"email/backend/internal/events"
	"email/backend/internal/model"
	"email/backend/internal/store"
)

func TestOutboxWorkerPublishesUpdatedFailureState(t *testing.T) {
	db := store.NewMemory()
	broker := events.NewBroker()
	account, err := db.CreateAccount(context.Background(), model.Account{
		Provider: model.ProviderMock,
		Email:    "owner@example.com",
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.EnqueueOutbox(context.Background(), model.SendRequest{
		AccountID: account.ID,
		To:        []model.Address{{Email: "reader@example.com"}},
		Subject:   "Queued",
	}); err != nil {
		t.Fatal(err)
	}
	ch, unsubscribe := broker.Subscribe()
	defer unsubscribe()
	worker := NewOutboxWorker(db, &Registry{
		connectors: map[model.Provider]Connector{
			model.ProviderMock: failingConnector{},
		},
	}, broker)

	worker.drain(context.Background())
	first := nextOutboxEvent(t, ch)
	if first.Status != "retry" || first.Attempts != 1 {
		t.Fatalf("expected first retry with one attempt, got %#v", first)
	}

	worker.drain(context.Background())
	second := nextOutboxEvent(t, ch)
	if second.Status != "retry" || second.Attempts != 2 {
		t.Fatalf("expected second retry with two attempts, got %#v", second)
	}

	worker.drain(context.Background())
	third := nextOutboxEvent(t, ch)
	if third.Status != "failed" || third.Attempts != 3 {
		t.Fatalf("expected third failure with three attempts, got %#v", third)
	}
}

func nextOutboxEvent(t *testing.T, ch <-chan model.Event) model.OutboxItem {
	t.Helper()
	event := <-ch
	item, ok := event.Payload.(model.OutboxItem)
	if !ok {
		t.Fatalf("unexpected payload %#v", event.Payload)
	}
	return item
}

type failingConnector struct{}

func (f failingConnector) Provider() model.Provider {
	return model.ProviderMock
}

func (f failingConnector) AuthorizeURL(state string) (string, error) {
	return "", nil
}

func (f failingConnector) Sync(ctx context.Context, account model.Account) error {
	return nil
}

func (f failingConnector) Send(ctx context.Context, account model.Account, req model.SendRequest) (string, error) {
	return "", errors.New("send failed")
}
