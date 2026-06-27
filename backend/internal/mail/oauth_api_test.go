package mail

import (
	"net/url"
	"strings"
	"testing"
)

func TestParseGmailHistoryCursor(t *testing.T) {
	historyID, ok := parseGmailHistoryCursor("gmail:history:12345")
	if !ok || historyID != "12345" {
		t.Fatalf("expected gmail history cursor, got %q %v", historyID, ok)
	}
	if _, ok := parseGmailHistoryCursor("1780000000000000000"); ok {
		t.Fatal("legacy timestamp cursor should not be treated as gmail history")
	}
}

func TestGmailHistoryEndpoint(t *testing.T) {
	endpoint := gmailHistoryEndpoint("12345", "next-page")
	parsed, err := url.Parse(endpoint)
	if err != nil {
		t.Fatal(err)
	}
	values := parsed.Query()
	if values.Get("startHistoryId") != "12345" {
		t.Fatalf("unexpected startHistoryId: %q", values.Get("startHistoryId"))
	}
	if values.Get("labelId") != "INBOX" {
		t.Fatalf("unexpected labelId: %q", values.Get("labelId"))
	}
	if values.Get("pageToken") != "next-page" {
		t.Fatalf("unexpected pageToken: %q", values.Get("pageToken"))
	}
	for _, historyType := range []string{"messageAdded", "messageDeleted", "labelAdded", "labelRemoved"} {
		if !containsString(values["historyTypes"], historyType) {
			t.Fatalf("missing history type %q in %v", historyType, values["historyTypes"])
		}
	}
	if !strings.Contains(values.Get("fields"), "historyId") {
		t.Fatalf("fields should request historyId, got %q", values.Get("fields"))
	}
}

func TestFilterDeletedGmailIDs(t *testing.T) {
	ids := filterDeletedGmailIDs(
		[]string{"keep", "deleted", "refetch"},
		map[string]bool{"deleted": true, "refetch": true},
		map[string]bool{"refetch": true},
	)
	if strings.Join(ids, ",") != "keep,refetch" {
		t.Fatalf("unexpected filtered ids: %v", ids)
	}
}

func TestNewerGmailHistoryID(t *testing.T) {
	if got := newerGmailHistoryID("9", "10"); got != "10" {
		t.Fatalf("expected numeric max 10, got %q", got)
	}
	if got := newerGmailHistoryID("10", "9"); got != "10" {
		t.Fatalf("expected numeric max 10, got %q", got)
	}
	if got := newerGmailHistoryID("", "abc"); got != "abc" {
		t.Fatalf("expected fallback candidate, got %q", got)
	}
}
