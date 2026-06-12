package config

import (
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type Config struct {
	Env                string
	Addr               string
	PublicURL          string
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
		Addr:               getenv("HTTP_ADDR", ":8080"),
		PublicURL:          getenv("PUBLIC_URL", "http://localhost:8080"),
		DataDir:            getenv("DATA_DIR", "./data"),
		OwnerEmail:         getenv("OWNER_EMAIL", "owner@example.com"),
		OwnerPassword:      getenv("OWNER_PASSWORD", "change-me-now"),
		OwnerPasswordHash:  os.Getenv("OWNER_PASSWORD_HASH"),
		OwnerTOTPSecret:    os.Getenv("OWNER_TOTP_SECRET"),
		AccessTTL:          15 * time.Minute,
		RefreshTTL:         30 * 24 * time.Hour,
		CORSAllowedOrigins: splitCSV(getenv("CORS_ALLOWED_ORIGINS", "http://localhost:8080,http://localhost:5173,http://localhost:3000")),
	}
	cfg.BlobDir = getenv("BLOB_DIR", filepath.Join(cfg.DataDir, "blobs"))

	key, err := loadMasterKey(cfg.Env)
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

func loadMasterKey(env string) ([]byte, error) {
	raw := strings.TrimSpace(os.Getenv("MASTER_KEY_BASE64"))
	if raw == "" {
		if env == "production" {
			return nil, errors.New("MASTER_KEY_BASE64 is required in production")
		}
		sum := sha256.Sum256([]byte("development-only-master-key"))
		return sum[:], nil
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
