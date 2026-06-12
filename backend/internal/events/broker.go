package events

import (
	"sync"
	"time"

	"email/backend/internal/model"
)

type Broker struct {
	mu          sync.RWMutex
	subscribers map[chan model.Event]struct{}
}

func NewBroker() *Broker {
	return &Broker{subscribers: make(map[chan model.Event]struct{})}
}

func (b *Broker) Subscribe() (chan model.Event, func()) {
	ch := make(chan model.Event, 32)
	b.mu.Lock()
	b.subscribers[ch] = struct{}{}
	b.mu.Unlock()
	return ch, func() {
		b.mu.Lock()
		delete(b.subscribers, ch)
		close(ch)
		b.mu.Unlock()
	}
}

func (b *Broker) Publish(event model.Event) {
	if event.At.IsZero() {
		event.At = time.Now()
	}
	b.mu.RLock()
	defer b.mu.RUnlock()
	for ch := range b.subscribers {
		select {
		case ch <- event:
		default:
		}
	}
}
