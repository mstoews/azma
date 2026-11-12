package storage

import (
	"context"
	"errors"
	"fmt"
	"mime"
	"os"
	"path/filepath"
	"strconv"
)

type Local struct{ Dir string }

func NewLocal(dir string) (*Local, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	return &Local{Dir: dir}, nil
}

func (l *Local) Describe() string { return "dir " + l.Dir }

func (l *Local) path(key string) (string, error) {
	k, ok := CleanKey(key)
	if !ok {
		return "", fmt.Errorf("storage: invalid key %q", key)
	}
	return filepath.Join(l.Dir, filepath.FromSlash(k)), nil
}

// Put writes to a temp file and renames, so a half-written file is never served.
func (l *Local) Put(_ context.Context, key string, data []byte, _ string) error {
	p, err := l.path(key)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(p), ".upload-*")
	if err != nil {
		return err
	}
	_, werr := tmp.Write(data)
	cerr := tmp.Close()
	if err := errors.Join(werr, cerr); err != nil {
		os.Remove(tmp.Name())
		return err
	}
	if err := os.Rename(tmp.Name(), p); err != nil {
		os.Remove(tmp.Name())
		return err
	}
	return nil
}

func (l *Local) Get(_ context.Context, key string) (*Object, error) {
	p, err := l.path(key)
	if err != nil {
		return nil, ErrNotFound
	}
	f, err := os.Open(p)
	if errors.Is(err, os.ErrNotExist) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	fi, err := f.Stat()
	if err != nil || fi.IsDir() {
		f.Close()
		return nil, ErrNotFound
	}
	return &Object{
		Body:        f,
		ContentType: mime.TypeByExtension(filepath.Ext(p)),
		Size:        fi.Size(),
		ModTime:     fi.ModTime(),
		ETag:        `"` + strconv.FormatInt(fi.ModTime().UnixNano(), 36) + "-" + strconv.FormatInt(fi.Size(), 36) + `"`,
	}, nil
}

func (l *Local) Delete(_ context.Context, key string) error {
	p, err := l.path(key)
	if err != nil {
		return err
	}
	if err := os.Remove(p); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}
