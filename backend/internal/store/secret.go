package store

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"io"
)

type SecretKeeper struct {
	block cipher.Block
}

func NewSecretKeeper(key []byte) (*SecretKeeper, error) {
	if len(key) == 0 {
		return &SecretKeeper{}, nil
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("create cipher: %w", err)
	}
	return &SecretKeeper{block: block}, nil
}

func (s *SecretKeeper) Encrypt(plaintext string) string {
	if s.block == nil || plaintext == "" {
		return plaintext
	}
	gcm, err := cipher.NewGCM(s.block)
	if err != nil {
		return plaintext
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return plaintext
	}
	return base64.StdEncoding.EncodeToString(gcm.Seal(nonce, nonce, []byte(plaintext), nil))
}

func (s *SecretKeeper) Decrypt(ciphertext string) string {
	if s.block == nil || ciphertext == "" {
		return ciphertext
	}
	data, err := base64.StdEncoding.DecodeString(ciphertext)
	if err != nil {
		return ciphertext
	}
	gcm, err := cipher.NewGCM(s.block)
	if err != nil {
		return ciphertext
	}
	nonceSize := gcm.NonceSize()
	if len(data) < nonceSize {
		return ciphertext
	}
	plaintext, err := gcm.Open(nil, data[:nonceSize], data[nonceSize:], nil)
	if err != nil {
		return ciphertext
	}
	return string(plaintext)
}
