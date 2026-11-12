package storage

import (
	"context"
	"errors"
	"io"
	"testing"
)

func TestCleanKey(t *testing.T) {
	// Cleaning is lexical and rooted, so ".." can never climb above the root.
	good := map[string]string{
		"2026/11/a.jpg":   "2026/11/a.jpg",
		"/2026//11/a.jpg": "2026/11/a.jpg",
		"a/../../b":       "b",
		"../etc/passwd":   "etc/passwd",
	}
	for in, want := range good {
		if got, ok := CleanKey(in); !ok || got != want {
			t.Errorf("CleanKey(%q) = %q,%v want %q", in, got, ok, want)
		}
	}
	for _, in := range []string{"", "..", "/", ".hidden", "a/.upload-1", `a\b`, "a\x00b"} {
		if k, ok := CleanKey(in); ok {
			t.Errorf("CleanKey(%q) = %q, want rejected", in, k)
		}
	}
}

func TestLocalRoundTrip(t *testing.T) {
	ctx := context.Background()
	l, err := NewLocal(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if err := l.Put(ctx, "2026/11/x.png", []byte("data"), "image/png"); err != nil {
		t.Fatal(err)
	}
	o, err := l.Get(ctx, "2026/11/x.png")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := io.ReadAll(o.Body)
	o.Body.Close()
	if string(b) != "data" || o.ContentType != "image/png" || o.ETag == "" {
		t.Fatalf("got %q %q %q", b, o.ContentType, o.ETag)
	}
	if err := l.Delete(ctx, "2026/11/x.png"); err != nil {
		t.Fatal(err)
	}
	if _, err := l.Get(ctx, "2026/11/x.png"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("after delete: %v", err)
	}
	if _, err := l.Get(ctx, "../../etc/passwd"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("traversal: %v", err)
	}
}
