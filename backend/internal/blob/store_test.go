package blob

import (
	"bytes"
	"crypto/sha256"
	"testing"
)

func TestStoreEncryptsAndLoadsBlob(t *testing.T) {
	key := sha256.Sum256([]byte("test key"))
	store, err := NewStore(t.TempDir(), key[:])
	if err != nil {
		t.Fatal(err)
	}
	saved, err := store.Save("hello.txt", "text/plain", []byte("hello"))
	if err != nil {
		t.Fatal(err)
	}
	got, err := store.Load(saved.ID, "hello.txt")
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, []byte("hello")) {
		t.Fatalf("unexpected blob: %q", got)
	}
}
