package mail

import (
	"context"
	"time"

	"email/backend/internal/events"
	"email/backend/internal/model"
	"email/backend/internal/store"
)

type OutboxWorker struct {
	db       store.MailStore
	registry *Registry
	broker   *events.Broker
}

func NewOutboxWorker(db store.MailStore, registry *Registry, broker *events.Broker) *OutboxWorker {
	return &OutboxWorker{db: db, registry: registry, broker: broker}
}

func (w *OutboxWorker) Start(ctx context.Context) {
	ticker := time.NewTicker(3 * time.Second)
	go func() {
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				w.drain(ctx)
			}
		}
	}()
}

func (w *OutboxWorker) drain(ctx context.Context) {
	items, err := w.db.PendingOutbox(ctx, 10)
	if err != nil {
		return
	}
	for _, item := range items {
		account, ok, err := w.db.GetAccount(ctx, item.AccountID)
		if err != nil {
			continue
		}
		if !ok {
			_, _ = w.db.MarkOutbox(ctx, item.ID, "failed", "account not found")
			continue
		}
		connector, ok := w.registry.For(account.Provider)
		if !ok {
			_, _ = w.db.MarkOutbox(ctx, item.ID, "failed", "connector not found")
			continue
		}
		if _, err := connector.Send(ctx, account, item.Payload); err != nil {
			status := "retry"
			if item.Attempts+1 >= 3 {
				status = "failed"
			}
			updated, _ := w.db.MarkOutbox(ctx, item.ID, status, err.Error())
			w.broker.Publish(model.Event{Type: "outbox.failed", AccountID: account.ID, Payload: updated})
			continue
		}
		updated, _ := w.db.MarkOutbox(ctx, item.ID, "sent", "")
		w.broker.Publish(model.Event{Type: "outbox.sent", AccountID: account.ID, Payload: updated})
	}
}
