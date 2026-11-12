package storage

import (
	"context"
	"errors"

	"cloud.google.com/go/storage"
)

// GCS stores objects in a bucket using Application Default Credentials: the
// Cloud Run service account in production, `gcloud auth
// application-default login` locally.
type GCS struct {
	client *storage.Client
	bucket *storage.BucketHandle
	name   string
	prefix string
}

func NewGCS(ctx context.Context, bucket, prefix string) (*GCS, error) {
	c, err := storage.NewClient(ctx)
	if err != nil {
		return nil, err
	}
	if prefix != "" && prefix[len(prefix)-1] != '/' {
		prefix += "/"
	}
	return &GCS{client: c, bucket: c.Bucket(bucket), name: bucket, prefix: prefix}, nil
}

func (g *GCS) Describe() string { return "gs://" + g.name + "/" + g.prefix }

func (g *GCS) obj(key string) (*storage.ObjectHandle, bool) {
	k, ok := CleanKey(key)
	if !ok {
		return nil, false
	}
	return g.bucket.Object(g.prefix + k), true
}

func (g *GCS) Put(ctx context.Context, key string, data []byte, contentType string) error {
	o, ok := g.obj(key)
	if !ok {
		return errors.New("storage: invalid key")
	}
	// DoesNotExist: upload keys carry a random component, so an existing
	// object means a collision, which must not overwrite someone's file.
	w := o.If(storage.Conditions{DoesNotExist: true}).NewWriter(ctx)
	w.ContentType = contentType
	w.CacheControl = "public, max-age=604800"
	if _, err := w.Write(data); err != nil {
		w.Close()
		return err
	}
	return w.Close()
}

func (g *GCS) Get(ctx context.Context, key string) (*Object, error) {
	o, ok := g.obj(key)
	if !ok {
		return nil, ErrNotFound
	}
	r, err := o.NewReader(ctx)
	if errors.Is(err, storage.ErrObjectNotExist) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &Object{
		Body:        r,
		ContentType: r.Attrs.ContentType,
		Size:        r.Attrs.Size,
		ModTime:     r.Attrs.LastModified,
		ETag:        `"` + itoa36(r.Attrs.Generation) + `"`,
	}, nil
}

func (g *GCS) Delete(ctx context.Context, key string) error {
	o, ok := g.obj(key)
	if !ok {
		return errors.New("storage: invalid key")
	}
	if err := o.Delete(ctx); err != nil && !errors.Is(err, storage.ErrObjectNotExist) {
		return err
	}
	return nil
}

func itoa36(n int64) string {
	const digits = "0123456789abcdefghijklmnopqrstuvwxyz"
	if n == 0 {
		return "0"
	}
	var b [16]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = digits[n%36]
		n /= 36
	}
	return string(b[i:])
}
