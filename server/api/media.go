package api

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	"github.com/mstoews/azma-associates/server/storage"
	"github.com/rs/zerolog/log"
	_ "golang.org/x/image/webp"
)

// allowedMedia maps sniffed content types to the extension files are saved
// with. SVG is deliberately absent: it can carry script.
var allowedMedia = map[string]string{
	"image/jpeg":      ".jpg",
	"image/png":       ".png",
	"image/gif":       ".gif",
	"image/webp":      ".webp",
	"application/pdf": ".pdf",
}

type mediaDTO struct {
	ID        int64     `json:"id"`
	URL       string    `json:"url"`
	Filename  string    `json:"filename"`
	MimeType  string    `json:"mimeType"`
	SizeBytes int64     `json:"sizeBytes"`
	Width     *int32    `json:"width"`
	Height    *int32    `json:"height"`
	Alt       string    `json:"alt"`
	Source    string    `json:"source"`
	CreatedAt time.Time `json:"createdAt"`
}

func toMediaDTO(m db.Medium) mediaDTO {
	return mediaDTO{m.ID, m.Url, m.Filename, m.MimeType, m.SizeBytes, int4Ptr(m.Width), int4Ptr(m.Height),
		m.Alt, m.Source, m.CreatedAt}
}

func (s *Server) listMedia(c *gin.Context) {
	rows, err := s.store.ListMedia(c.Request.Context())
	if err != nil {
		dbError(c, err)
		return
	}
	out := make([]mediaDTO, len(rows))
	for i, m := range rows {
		out[i] = toMediaDTO(m)
	}
	c.JSON(http.StatusOK, out)
}

var unsafeName = regexp.MustCompile(`[^a-z0-9]+`)

// safeBaseName turns an uploaded filename into a short, URL-safe stem.
func safeBaseName(name string) string {
	base := strings.TrimSuffix(filepath.Base(name), filepath.Ext(name))
	base = strings.Trim(unsafeName.ReplaceAllString(strings.ToLower(base), "-"), "-")
	if len(base) > 60 {
		base = strings.Trim(base[:60], "-")
	}
	if base == "" {
		base = "file"
	}
	return base
}

func (s *Server) uploadMedia(c *gin.Context) {
	max := s.config.MediaMaxBytes
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, max+(1<<20))
	fh, err := c.FormFile("file")
	if err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			c.AbortWithStatusJSON(http.StatusRequestEntityTooLarge, gin.H{"error": "file is too large"})
			return
		}
		badRequest(c, "expected a multipart form with a 'file' field")
		return
	}
	if fh.Size > max {
		c.AbortWithStatusJSON(http.StatusRequestEntityTooLarge, gin.H{
			"error": "file is too large (limit " + strconv.FormatInt(max>>20, 10) + " MB)",
		})
		return
	}
	f, err := fh.Open()
	if err != nil {
		badRequest(c, "could not read upload")
		return
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, max+1))
	if err != nil || int64(len(data)) > max {
		badRequest(c, "could not read upload")
		return
	}

	// Trust the bytes, not the client's Content-Type or filename.
	mime := http.DetectContentType(data)
	if i := strings.IndexByte(mime, ';'); i >= 0 {
		mime = mime[:i]
	}
	ext, ok := allowedMedia[mime]
	if !ok {
		c.AbortWithStatusJSON(http.StatusUnsupportedMediaType, gin.H{
			"error": "unsupported file type " + mime + "; allowed: JPEG, PNG, GIF, WebP, PDF",
		})
		return
	}

	var width, height pgtype.Int4
	if strings.HasPrefix(mime, "image/") {
		cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
		if err != nil {
			badRequest(c, "the image could not be decoded")
			return
		}
		width = pgtype.Int4{Int32: int32(cfg.Width), Valid: true}
		height = pgtype.Int4{Int32: int32(cfg.Height), Valid: true}
	}

	rnd := make([]byte, 4)
	_, _ = rand.Read(rnd)
	now := s.now().UTC()
	rel := path.Join(now.Format("2006"), now.Format("01"), hex.EncodeToString(rnd)+"-"+safeBaseName(fh.Filename)+ext)
	if err := s.media.Put(c.Request.Context(), rel, data, mime); err != nil {
		log.Error().Err(err).Str("store", s.media.Describe()).Msg("store media")
		c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "could not store file"})
		return
	}

	m, err := s.store.CreateMedia(c.Request.Context(), db.CreateMediaParams{
		Url: s.config.MediaURLPrefix + "/" + rel, Filename: truncate(filepath.Base(fh.Filename), 255),
		StoragePath: pgtype.Text{String: rel, Valid: true}, MimeType: mime, SizeBytes: int64(len(data)),
		Width: width, Height: height, Alt: strings.TrimSpace(c.PostForm("alt")), Source: "upload",
		CreatedBy: currentUserID(c),
	})
	if err != nil {
		_ = s.media.Delete(context.Background(), rel)
		dbError(c, err)
		return
	}
	s.audit(c, "upload", "media", strconv.FormatInt(m.ID, 10), gin.H{"url": m.Url, "size": m.SizeBytes})
	c.JSON(http.StatusCreated, toMediaDTO(m))
}

func (s *Server) updateMedia(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	var in struct {
		Alt string `json:"alt"`
	}
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	m, err := s.store.UpdateMediaAlt(c.Request.Context(), db.UpdateMediaAltParams{ID: id, Alt: strings.TrimSpace(in.Alt)})
	if err != nil {
		dbError(c, err)
		return
	}
	c.JSON(http.StatusOK, toMediaDTO(m))
}

// deleteMedia refuses (409) while the file is referenced on the site unless
// ?force=1 is given. Files imported from WordPress ship with the front-end
// build, so only their library entry is removed.
func (s *Server) deleteMedia(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	ctx := c.Request.Context()
	m, err := s.store.GetMedia(ctx, id)
	if err != nil {
		dbError(c, err)
		return
	}
	if c.Query("force") != "1" {
		n, err := s.store.CountMediaUsage(ctx, m.Url)
		if err != nil {
			dbError(c, err)
			return
		}
		if n > 0 {
			c.AbortWithStatusJSON(http.StatusConflict, gin.H{
				"error": "this file is used in " + strconv.Itoa(int(n)) + " place(s) on the site", "usage": n,
			})
			return
		}
	}
	if err := s.store.DeleteMedia(ctx, id); err != nil && !errors.Is(err, pgx.ErrNoRows) {
		dbError(c, err)
		return
	}
	if m.StoragePath.Valid {
		if err := s.media.Delete(ctx, m.StoragePath.String); err != nil {
			log.Warn().Err(err).Str("key", m.StoragePath.String).Msg("media file not removed")
		}
	}
	s.audit(c, "delete", "media", strconv.FormatInt(id, 10), gin.H{"url": m.Url})
	c.Status(http.StatusNoContent)
}

// serveMedia streams an uploaded file from the media store. The bucket (if
// any) stays private; this handler is the only way files are read.
func (s *Server) serveMedia(c *gin.Context) {
	key, ok := storage.CleanKey(c.Param("key"))
	if !ok {
		c.Status(http.StatusNotFound)
		return
	}
	obj, err := s.media.Get(c.Request.Context(), key)
	if errors.Is(err, storage.ErrNotFound) {
		c.Status(http.StatusNotFound)
		return
	}
	if err != nil {
		log.Error().Err(err).Str("key", key).Msg("read media")
		c.Status(http.StatusBadGateway)
		return
	}
	defer obj.Body.Close()

	h := c.Writer.Header()
	h.Set("Cache-Control", "public, max-age=604800")
	if obj.ETag != "" {
		h.Set("ETag", obj.ETag)
		if c.GetHeader("If-None-Match") == obj.ETag {
			c.Status(http.StatusNotModified)
			return
		}
	}
	ct := obj.ContentType
	if ct == "" {
		ct = "application/octet-stream"
	}
	h.Set("Content-Type", ct)
	h.Set("Content-Length", strconv.FormatInt(obj.Size, 10))
	if !obj.ModTime.IsZero() {
		h.Set("Last-Modified", obj.ModTime.UTC().Format(http.TimeFormat))
	}
	// Uploads are only images and PDFs, but never let a browser treat one as
	// a page that can run script on this origin.
	h.Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; sandbox")
	c.Status(http.StatusOK)
	if c.Request.Method == http.MethodHead {
		return
	}
	_, _ = io.Copy(c.Writer, obj.Body)
}

// serveSPA serves the built Angular site from STATIC_DIR, falling back to
// index.html so client-side routes (/admin, /profile/x) load on refresh.
func (s *Server) serveSPA(c *gin.Context) {
	p := c.Request.URL.Path
	if strings.HasPrefix(p, "/api/") || (c.Request.Method != http.MethodGet && c.Request.Method != http.MethodHead) {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	// path.Clean on a rooted path cannot climb above the root.
	rel := filepath.FromSlash(path.Clean("/" + p))
	full := filepath.Join(s.config.StaticDir, rel)
	if fi, err := os.Stat(full); err == nil && !fi.IsDir() {
		if isHashedAsset(p) {
			c.Header("Cache-Control", "public, max-age=31536000, immutable")
		} else {
			c.Header("Cache-Control", "public, max-age=3600")
		}
		c.File(full)
		return
	}
	if path.Ext(p) != "" {
		// A missing asset should 404, not return the HTML shell.
		c.Status(http.StatusNotFound)
		return
	}
	c.Header("Cache-Control", "no-cache")
	c.File(filepath.Join(s.config.StaticDir, "index.html"))
}

var hashedAsset = regexp.MustCompile(`-[A-Z0-9]{8}\.(js|css)$`)

func isHashedAsset(p string) bool { return hashedAsset.MatchString(p) }
