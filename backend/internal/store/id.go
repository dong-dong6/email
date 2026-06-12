package store

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"time"
)

func NewID(prefix string) string {
	b := make([]byte, 12)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("%s_%d", prefix, time.Now().UnixNano())
	}
	return prefix + "_" + base64.RawURLEncoding.EncodeToString(b)
}
