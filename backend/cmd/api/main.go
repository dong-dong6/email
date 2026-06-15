package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"email/backend/internal/auth"
	"email/backend/internal/blob"
	"email/backend/internal/config"
	"email/backend/internal/events"
	"email/backend/internal/httpapi"
	"email/backend/internal/mail"
	"email/backend/internal/store"
)

func main() {
	if err := run(); err != nil {
		slog.Error("server stopped", "error", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(cfg.DataDir, 0o700); err != nil {
		return err
	}
	blobStore, err := blob.NewStore(cfg.BlobDir, cfg.MasterKey)
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	db, err := store.NewMemoryWithKey(cfg.MasterKey)
	if err != nil {
		return fmt.Errorf("init memory store: %w", err)
	}

	var userStore auth.UserStore
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL != "" {
		pgStore, err := store.NewPostgres(ctx, databaseURL)
		if err != nil {
			slog.Warn("failed to connect to postgres, using config-based auth", "error", err)
		} else {
			defer pgStore.Close()
			userStore = store.NewUserStoreAdapter(pgStore)
			slog.Info("PostgreSQL connected for user management")
		}
	}

	broker := events.NewBroker()
	authSvc := auth.NewService(cfg, userStore)
	registry := mail.NewRegistry(db, broker)
	mail.NewOutboxWorker(db, registry, broker).Start(ctx)

	api := httpapi.NewServer(cfg, authSvc, db, blobStore, registry, broker)
	server := &http.Server{
		Addr:              cfg.Addr,
		Handler:           api.Routes(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      0,
		IdleTimeout:       120 * time.Second,
	}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}()
	slog.Info("email api listening", "addr", cfg.Addr, "env", cfg.Env)
	err = server.ListenAndServe()
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}
