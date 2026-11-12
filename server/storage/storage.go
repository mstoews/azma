// Package storage holds uploaded media. Files live either in a local folder
// (development, or a container with a mounted volume) or in a Google Cloud
// Storage bucket (Cloud Run, whose disk does not survive restarts).
//
// Keys are slash-separated paths such as "2026/11/ab12cd-photo.jpg". The API
// server streams objects back under MEDIA_URL_PREFIX, so the bucket can stay
// private and URLs do not change when the backend does.
package storage

import (
	"context"
	"errors"
	"io"
	"path"
	"strings"
	"time"
)

var ErrNotFound = errors.New("storage: object not found")

type Object struct {
	Body        io.ReadCloser
	ContentType string
	Size        int64
	ModTime     time.Time
	ETag        string
}

type Store interface {
	Put(ctx context.Context, key string, data []byte, contentType string) error
	Get(ctx context.Context, key string) (*Object, error)
	Delete(ctx context.Context, key string) error
	// Describe names the backend for logs, e.g. "gs://bucket" or "dir ./media".
	Describe() string
}

// CleanKey normalises a key and rejects anything that could escape the
// store's root ("..", absolute paths, empty names).
func CleanKey(key string) (string, bool) {
	if key == "" || strings.ContainsRune(key, '\\') || strings.ContainsRune(key, 0) {
		return "", false
	}
	k := strings.TrimPrefix(path.Clean("/"+key), "/")
	if k == "" || k == "." || strings.HasPrefix(k, ".") || strings.Contains(k, "/.") {
		return "", false
	}
	return k, true
}
