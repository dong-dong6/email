package auth

import (
	"errors"
	"testing"
	"time"

	"email/backend/internal/config"
)

func TestPasswordHashRoundTrip(t *testing.T) {
	hash, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatal(err)
	}
	if !VerifyPassword("correct horse battery staple", hash) {
		t.Fatal("expected password to verify")
	}
	if VerifyPassword("wrong", hash) {
		t.Fatal("wrong password verified")
	}
}

func TestRefreshPreservesDatabaseUserIdentity(t *testing.T) {
	hash, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatal(err)
	}
	var key [32]byte
	service := NewService(config.Config{
		MasterKey:  key[:],
		AccessTTL:  time.Minute,
		RefreshTTL: time.Hour,
	}, fakeUserStore{
		email:        "admin@example.com",
		passwordHash: hash,
		role:         "admin",
	})

	pair, err := service.Login("ADMIN@example.com", "correct horse battery staple", "")
	if err != nil {
		t.Fatal(err)
	}
	refreshed, err := service.Refresh(pair.RefreshToken)
	if err != nil {
		t.Fatal(err)
	}
	claims, err := service.Verify(refreshed.AccessToken, "access")
	if err != nil {
		t.Fatal(err)
	}
	if claims.Email != "admin@example.com" {
		t.Fatalf("expected refreshed token to keep database user email, got %q", claims.Email)
	}
	if claims.Subject != "admin" {
		t.Fatalf("expected refreshed token to keep role, got %q", claims.Subject)
	}
}

type fakeUserStore struct {
	email        string
	passwordHash string
	role         string
}

func (s fakeUserStore) GetUserByEmail(email string) (id, passwordHash, role string, err error) {
	if email != s.email {
		return "", "", "", errors.New("not found")
	}
	return "usr_test", s.passwordHash, s.role, nil
}

func (s fakeUserStore) HasUsers() (bool, error) {
	return true, nil
}

func (s fakeUserStore) CreateUser(email, passwordHash, role string) (string, error) {
	return "", errors.New("not implemented")
}
