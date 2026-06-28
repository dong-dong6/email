package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/base32"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"hash"
	"strconv"
	"strings"
	"sync"
	"time"

	"email/backend/internal/config"
)

type UserStore interface {
	GetUserByEmail(email string) (id, passwordHash, role string, err error)
	HasUsers() (bool, error)
	CreateUser(email, passwordHash, role string) (string, error)
}

type Service struct {
	email        string
	password     string
	passwordHash string
	totpSecret   string
	key          []byte
	accessTTL    time.Duration
	refreshTTL   time.Duration
	mu           sync.Mutex
	refresh      map[string]time.Time
	userStore    UserStore
}

type TokenPair struct {
	AccessToken  string    `json:"access_token"`
	RefreshToken string    `json:"refresh_token"`
	ExpiresAt    time.Time `json:"expires_at"`
}

type Claims struct {
	Subject string `json:"sub"`
	Email   string `json:"email"`
	Type    string `json:"typ"`
	Expiry  int64  `json:"exp"`
	ID      string `json:"jti"`
}

func NewService(cfg config.Config, userStore UserStore) *Service {
	return &Service{
		email:        strings.ToLower(cfg.OwnerEmail),
		password:     cfg.OwnerPassword,
		passwordHash: cfg.OwnerPasswordHash,
		totpSecret:   cfg.OwnerTOTPSecret,
		key:          cfg.MasterKey,
		accessTTL:    cfg.AccessTTL,
		refreshTTL:   cfg.RefreshTTL,
		refresh:      make(map[string]time.Time),
		userStore:    userStore,
	}
}

func (s *Service) Login(email, password, totp string) (TokenPair, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	if s.userStore != nil {
		_, passwordHash, role, err := s.userStore.GetUserByEmail(email)
		if err != nil {
			return TokenPair{}, errors.New("invalid credentials")
		}
		if !VerifyPassword(password, passwordHash) {
			return TokenPair{}, errors.New("invalid credentials")
		}
		return s.issuePairForUser(email, role)
	}
	if email != s.email {
		return TokenPair{}, errors.New("invalid credentials")
	}
	if !s.verifyPassword(password) {
		return TokenPair{}, errors.New("invalid credentials")
	}
	if s.totpSecret != "" && !VerifyTOTP(s.totpSecret, totp, time.Now()) {
		return TokenPair{}, errors.New("invalid totp code")
	}
	return s.issuePair()
}

func (s *Service) Refresh(refreshToken string) (TokenPair, error) {
	claims, err := s.Verify(refreshToken, "refresh")
	if err != nil {
		return TokenPair{}, err
	}
	s.mu.Lock()
	expiry, ok := s.refresh[claims.ID]
	if !ok || time.Now().After(expiry) {
		s.mu.Unlock()
		return TokenPair{}, errors.New("refresh token expired")
	}
	delete(s.refresh, claims.ID)
	s.mu.Unlock()
	return s.issuePairForUser(claims.Email, claims.Subject)
}

func (s *Service) Verify(token, tokenType string) (Claims, error) {
	var claims Claims
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return claims, errors.New("malformed token")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return claims, err
	}
	expected := sign(payload, s.key)
	if !hmac.Equal([]byte(parts[1]), []byte(expected)) {
		return claims, errors.New("invalid token signature")
	}
	if err := json.Unmarshal(payload, &claims); err != nil {
		return claims, err
	}
	if claims.Type != tokenType {
		return claims, errors.New("invalid token type")
	}
	if time.Now().Unix() > claims.Expiry {
		return claims, errors.New("token expired")
	}
	return claims, nil
}

func (s *Service) issuePair() (TokenPair, error) {
	return s.issuePairForUser(s.email, "admin")
}

func (s *Service) issuePairForUser(email, role string) (TokenPair, error) {
	now := time.Now()
	accessID := randomID("atk")
	refreshID := randomID("rtk")
	accessExpiry := now.Add(s.accessTTL)
	refreshExpiry := now.Add(s.refreshTTL)

	access, err := s.signClaims(Claims{Subject: role, Email: email, Type: "access", Expiry: accessExpiry.Unix(), ID: accessID})
	if err != nil {
		return TokenPair{}, err
	}
	refresh, err := s.signClaims(Claims{Subject: role, Email: email, Type: "refresh", Expiry: refreshExpiry.Unix(), ID: refreshID})
	if err != nil {
		return TokenPair{}, err
	}
	s.mu.Lock()
	s.refresh[refreshID] = refreshExpiry
	s.mu.Unlock()
	return TokenPair{AccessToken: access, RefreshToken: refresh, ExpiresAt: accessExpiry}, nil
}

func (s *Service) Register(email, password string) (string, error) {
	if s.userStore == nil {
		return "", errors.New("registration not supported")
	}
	hasUsers, err := s.userStore.HasUsers()
	if err != nil {
		return "", err
	}
	if hasUsers {
		return "", errors.New("admin already exists")
	}
	hash, err := HashPassword(password)
	if err != nil {
		return "", err
	}
	return s.userStore.CreateUser(email, hash, "admin")
}

func (s *Service) HasUsers() bool {
	if s.userStore == nil {
		return true
	}
	has, err := s.userStore.HasUsers()
	if err != nil {
		return true
	}
	return has
}

func (s *Service) signClaims(claims Claims) (string, error) {
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	encoded := base64.RawURLEncoding.EncodeToString(payload)
	return encoded + "." + sign(payload, s.key), nil
}

func sign(payload, key []byte) string {
	mac := hmac.New(sha256.New, key)
	mac.Write(payload)
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func (s *Service) verifyPassword(password string) bool {
	if s.passwordHash != "" {
		return VerifyPassword(password, s.passwordHash)
	}
	return subtleEqual(password, s.password)
}

func HashPassword(password string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	hash := pbkdf2([]byte(password), salt, 210000, 32, sha256.New)
	return fmt.Sprintf("pbkdf2_sha256$210000$%s$%s", base64.RawStdEncoding.EncodeToString(salt), base64.RawStdEncoding.EncodeToString(hash)), nil
}

func VerifyPassword(password, encoded string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 4 || parts[0] != "pbkdf2_sha256" {
		return false
	}
	iterations, err := strconv.Atoi(parts[1])
	if err != nil || iterations <= 0 {
		return false
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[2])
	if err != nil {
		return false
	}
	want, err := base64.RawStdEncoding.DecodeString(parts[3])
	if err != nil {
		return false
	}
	got := pbkdf2([]byte(password), salt, iterations, len(want), sha256.New)
	return hmac.Equal(got, want)
}

func pbkdf2(password, salt []byte, iter, keyLen int, h func() hash.Hash) []byte {
	prf := hmac.New(h, password)
	hashLen := prf.Size()
	numBlocks := (keyLen + hashLen - 1) / hashLen
	var out []byte
	var block [4]byte
	for i := 1; i <= numBlocks; i++ {
		binary.BigEndian.PutUint32(block[:], uint32(i))
		prf.Reset()
		prf.Write(salt)
		prf.Write(block[:])
		u := prf.Sum(nil)
		t := append([]byte(nil), u...)
		for j := 1; j < iter; j++ {
			prf.Reset()
			prf.Write(u)
			u = prf.Sum(nil)
			for k := range t {
				t[k] ^= u[k]
			}
		}
		out = append(out, t...)
	}
	return out[:keyLen]
}

func VerifyTOTP(secret, code string, at time.Time) bool {
	code = strings.TrimSpace(code)
	if len(code) != 6 {
		return false
	}
	secret = strings.ToUpper(strings.ReplaceAll(secret, " ", ""))
	key, err := base32.StdEncoding.WithPadding(base32.NoPadding).DecodeString(secret)
	if err != nil {
		return false
	}
	step := at.Unix() / 30
	for offset := int64(-1); offset <= 1; offset++ {
		if totpCode(key, step+offset) == code {
			return true
		}
	}
	return false
}

func totpCode(key []byte, counter int64) string {
	var buf [8]byte
	binary.BigEndian.PutUint64(buf[:], uint64(counter))
	mac := hmac.New(sha1.New, key)
	mac.Write(buf[:])
	sum := mac.Sum(nil)
	offset := sum[len(sum)-1] & 0x0f
	value := (int(sum[offset])&0x7f)<<24 | (int(sum[offset+1])&0xff)<<16 | (int(sum[offset+2])&0xff)<<8 | (int(sum[offset+3]) & 0xff)
	return fmt.Sprintf("%06d", value%1000000)
}

func randomID(prefix string) string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("%s_%d", prefix, time.Now().UnixNano())
	}
	return prefix + "_" + base64.RawURLEncoding.EncodeToString(b)
}

func subtleEqual(a, b string) bool {
	return hmac.Equal([]byte(a), []byte(b))
}
