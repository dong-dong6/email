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
	setupLogger(cfg.LogLevel)
	if err := os.MkdirAll(cfg.DataDir, 0o700); err != nil {
		return err
	}
	blobStore, err := blob.NewStore(cfg.BlobDir, cfg.MasterKey)
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	var db store.MailStore
	var userStore auth.UserStore
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL != "" {
		pgStore, err := store.NewPostgres(ctx, databaseURL, cfg.MasterKey)
		if err != nil {
			return fmt.Errorf("init postgres store: %w", err)
		}
		defer pgStore.Close()
		db = pgStore
		userStore = store.NewUserStoreAdapter(pgStore)
		slog.Info("PostgreSQL connected for mailbox and user management")
	} else {
		memoryStore, err := store.NewMemoryWithKey(cfg.MasterKey)
		if err != nil {
			return fmt.Errorf("init memory store: %w", err)
		}
		db = memoryStore
		slog.Warn("DATABASE_URL is empty; using in-memory mailbox store")
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

func setupLogger(levelName string) {
	var level slog.Level
	switch levelName {
	case "debug":
		level = slog.LevelDebug
	case "warn", "warning":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	default:
		level = slog.LevelInfo
		levelName = "info"
	}
	handler := slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: level})
	slog.SetDefault(slog.New(handler))
	slog.Info("logger configured", "level", levelName)
}
