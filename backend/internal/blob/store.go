package blob

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

type Store struct {
	dir string
	key []byte
}

type SavedBlob struct {
	ID          string `json:"id"`
	ContentType string `json:"content_type"`
	Size        int64  `json:"size"`
}

func NewStore(dir string, key []byte) (*Store, error) {
	if len(key) != 32 {
		return nil, errors.New("blob master key must be 32 bytes")
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	return &Store{dir: dir, key: key}, nil
}

func (s *Store) Save(name, contentType string, data []byte) (SavedBlob, error) {
	if contentType == "" {
		contentType = http.DetectContentType(data)
	}
	block, err := aes.NewCipher(s.key)
	if err != nil {
		return SavedBlob{}, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return SavedBlob{}, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return SavedBlob{}, err
	}
	ciphertext := gcm.Seal(nonce, nonce, data, []byte(cleanName(name)))
	sum := sha256.Sum256(ciphertext)
	id := base64.RawURLEncoding.EncodeToString(sum[:])
	path := s.path(id)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return SavedBlob{}, err
	}
	if err := os.WriteFile(path, ciphertext, 0o600); err != nil {
		return SavedBlob{}, err
	}
	return SavedBlob{ID: id, ContentType: contentType, Size: int64(len(data))}, nil
}

func (s *Store) Load(id, name string) ([]byte, error) {
	ciphertext, err := os.ReadFile(s.path(id))
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(s.key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	if len(ciphertext) < gcm.NonceSize() {
		return nil, errors.New("invalid blob")
	}
	nonce := ciphertext[:gcm.NonceSize()]
	body := ciphertext[gcm.NonceSize():]
	return gcm.Open(nil, nonce, body, []byte(cleanName(name)))
}

func (s *Store) SaveReader(name, contentType string, r io.Reader, maxBytes int64) (SavedBlob, error) {
	data, err := io.ReadAll(io.LimitReader(r, maxBytes+1))
	if err != nil {
		return SavedBlob{}, err
	}
	if int64(len(data)) > maxBytes {
		return SavedBlob{}, errors.New("blob too large")
	}
	return s.Save(name, contentType, data)
}

func (s *Store) path(id string) string {
	clean := strings.Map(func(r rune) rune {
		if r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_' {
			return r
		}
		return -1
	}, id)
	if len(clean) < 4 {
		clean = "blob" + clean
	}
	return filepath.Join(s.dir, clean[:2], clean[2:4], clean)
}

func cleanName(name string) string {
	name = filepath.Base(strings.ReplaceAll(name, "\\", "/"))
	if name == "." || name == "/" || name == "" {
		return "blob"
	}
	return name
}
