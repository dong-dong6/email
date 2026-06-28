package config

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type Config struct {
	Env                string
	LogLevel           string
	Addr               string
	DataDir            string
	BlobDir            string
	OwnerEmail         string
	OwnerPassword      string
	OwnerPasswordHash  string
	OwnerTOTPSecret    string
	MasterKey          []byte
	AccessTTL          time.Duration
	RefreshTTL         time.Duration
	CORSAllowedOrigins []string
}

func Load() (Config, error) {
	cfg := Config{
		Env:                getenv("APP_ENV", "development"),
		LogLevel:           strings.ToLower(getenv("LOG_LEVEL", "info")),
		Addr:               getenv("HTTP_ADDR", ":8080"),
		DataDir:            getenv("DATA_DIR", "./data"),
		OwnerEmail:         os.Getenv("OWNER_EMAIL"),
		OwnerPassword:      os.Getenv("OWNER_PASSWORD"),
		OwnerPasswordHash:  os.Getenv("OWNER_PASSWORD_HASH"),
		OwnerTOTPSecret:    os.Getenv("OWNER_TOTP_SECRET"),
		AccessTTL:          15 * time.Minute,
		RefreshTTL:         30 * 24 * time.Hour,
		CORSAllowedOrigins: splitCSV(getenv("CORS_ALLOWED_ORIGINS", "http://localhost:8080,http://localhost:5173,http://localhost:3000")),
	}
	cfg.BlobDir = getenv("BLOB_DIR", filepath.Join(cfg.DataDir, "blobs"))

	key, err := loadMasterKey(cfg.DataDir)
	if err != nil {
		return Config{}, err
	}
	cfg.MasterKey = key
	return cfg, nil
}

func getenv(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func splitCSV(value string) []string {
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}

func loadMasterKey(dataDir string) ([]byte, error) {
	raw := strings.TrimSpace(os.Getenv("MASTER_KEY_BASE64"))
	if raw == "" {
		return loadOrCreateMasterKeyFile(dataDir)
	}
	key, err := base64.StdEncoding.DecodeString(raw)
	if err != nil {
		return nil, err
	}
	if len(key) != 32 {
		return nil, errors.New("MASTER_KEY_BASE64 must decode to 32 bytes")
	}
	return key, nil
}

func loadOrCreateMasterKeyFile(dataDir string) ([]byte, error) {
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		return nil, err
	}
	path := filepath.Join(dataDir, "master.key")
	if data, err := os.ReadFile(path); err == nil {
		key, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(data)))
		if err != nil {
			return nil, err
		}
		if len(key) != 32 {
			return nil, errors.New("stored master key must decode to 32 bytes")
		}
		return key, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		return nil, err
	}
	encoded := base64.StdEncoding.EncodeToString(key)
	if err := os.WriteFile(path, []byte(encoded+"\n"), 0o600); err != nil {
		return nil, err
	}
	return key, nil
}
