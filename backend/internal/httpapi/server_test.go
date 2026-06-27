package httpapi

import (
	"testing"

	"email/backend/internal/model"
)

func TestNormalizeSendRequestRequiresRecipient(t *testing.T) {
	req := model.SendRequest{AccountID: " acc_1 "}
	account := model.Account{
		Email:       "owner@example.com",
		DisplayName: "Owner",
	}

	if err := normalizeSendRequest(&req, account); err == nil {
		t.Fatal("expected missing recipient error")
	}
}

func TestNormalizeSendRequestValidatesRecipientsAndForcesFrom(t *testing.T) {
	req := model.SendRequest{
		AccountID: " acc_1 ",
		From:      &model.Address{Name: "Spoof", Email: "spoof@example.com"},
		To: []model.Address{
			{Email: "Reader <reader@example.com>"},
		},
		Cc: []model.Address{
			{Name: " Team ", Email: "team@example.com"},
		},
		Subject: "  Hello  ",
	}
	account := model.Account{
		Email:       "owner@example.com",
		DisplayName: "Owner",
	}

	if err := normalizeSendRequest(&req, account); err != nil {
		t.Fatal(err)
	}
	if req.From == nil || req.From.Email != "owner@example.com" || req.From.Name != "Owner" {
		t.Fatalf("unexpected from address: %#v", req.From)
	}
	if req.To[0].Email != "reader@example.com" || req.To[0].Name != "Reader" {
		t.Fatalf("recipient was not normalized: %#v", req.To[0])
	}
	if req.Cc[0].Name != "Team" {
		t.Fatalf("cc name was not trimmed: %#v", req.Cc[0])
	}
	if req.Subject != "Hello" || req.AccountID != "acc_1" {
		t.Fatalf("request fields were not normalized: %#v", req)
	}
}

func TestNormalizeSendRequestRejectsInvalidRecipient(t *testing.T) {
	req := model.SendRequest{
		AccountID: "acc_1",
		To: []model.Address{
			{Email: "not-an-address"},
		},
	}
	account := model.Account{
		Email:       "owner@example.com",
		DisplayName: "Owner",
	}

	if err := normalizeSendRequest(&req, account); err == nil {
		t.Fatal("expected invalid recipient error")
	}
}
