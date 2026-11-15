// Resumes. Unlike CMS media, these are confidential: they are stored under
// resumes/ in the same object store but are never served from a public path,
// only streamed back to the person who uploaded them or to a consultant.
package api

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"io"
	"net/http"
	"net/url"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	md "github.com/mstoews/azma-associates/server/middleware"
	"github.com/mstoews/azma-associates/server/storage"
	"github.com/rs/zerolog/log"
)

const resumePrefix = "resumes"

type resumeDTO struct {
	ID          int64     `json:"id"`
	Filename    string    `json:"filename"`
	MimeType    string    `json:"mimeType"`
	SizeBytes   int64     `json:"sizeBytes"`
	CreatedAt   time.Time `json:"createdAt"`
	DownloadURL string    `json:"downloadUrl"`
}

func toResumeDTO(r db.Resume) resumeDTO {
	return resumeDTO{r.ID, r.Filename, r.MimeType, r.SizeBytes, r.CreatedAt,
		"/api/v1/resumes/" + strconv.FormatInt(r.ID, 10) + "/file"}
}

// Magic numbers for the three formats a resume arrives in. Word documents
// cannot be identified from their bytes alone (.docx is a ZIP, .doc an OLE2
// container), so the extension has to agree with the container.
var (
	magicPDF  = []byte("%PDF-")
	magicZIP  = []byte("PK\x03\x04")
	magicOLE2 = []byte{0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1}
)

const (
	mimePDF  = "application/pdf"
	mimeDOC  = "application/msword"
	mimeDOCX = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
)

// detectResumeType trusts the bytes first and the filename only to tell two
// container formats apart.
func detectResumeType(data []byte, filename string) (mime, ext string, ok bool) {
	switch strings.ToLower(filepath.Ext(filename)) {
	case ".pdf":
		if bytes.HasPrefix(data, magicPDF) {
			return mimePDF, ".pdf", true
		}
	case ".docx":
		if bytes.HasPrefix(data, magicZIP) {
			return mimeDOCX, ".docx", true
		}
	case ".doc":
		if bytes.HasPrefix(data, magicOLE2) {
			return mimeDOC, ".doc", true
		}
	default:
		// No usable extension: accept it only if it really is a PDF.
		if bytes.HasPrefix(data, magicPDF) {
			return mimePDF, ".pdf", true
		}
	}
	return "", "", false
}

func (s *Server) listResumes(c *gin.Context) {
	u, _ := md.CurrentUser(c)
	rows, err := s.store.ListResumes(c.Request.Context(), u.ID)
	if err != nil {
		dbError(c, err)
		return
	}
	out := make([]resumeDTO, len(rows))
	for i, r := range rows {
		out[i] = toResumeDTO(r)
	}
	c.JSON(http.StatusOK, out)
}

// uploadResume takes a multipart form with a 'file' field, the same shape the
// media library uses.
func (s *Server) uploadResume(c *gin.Context) {
	u, _ := md.CurrentUser(c)
	ctx := c.Request.Context()

	n, err := s.store.CountResumes(ctx, u.ID)
	if err != nil {
		dbError(c, err)
		return
	}
	if int(n) >= maxResumesPerUser {
		c.AbortWithStatusJSON(http.StatusConflict, gin.H{
			"error": "you already have " + strconv.Itoa(maxResumesPerUser) + " documents on file; delete one first",
		})
		return
	}

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
	if len(data) == 0 {
		badRequest(c, "the file is empty")
		return
	}
	mime, ext, ok := detectResumeType(data, fh.Filename)
	if !ok {
		c.AbortWithStatusJSON(http.StatusUnsupportedMediaType, gin.H{
			"error": "resumes must be a PDF or a Word document (.pdf, .doc, .docx)",
		})
		return
	}

	rnd := make([]byte, 8)
	_, _ = rand.Read(rnd)
	now := s.now().UTC()
	key := path.Join(resumePrefix, now.Format("2006"), now.Format("01"),
		hex.EncodeToString(rnd)+"-"+safeBaseName(fh.Filename)+ext)
	if err := s.media.Put(ctx, key, data, mime); err != nil {
		log.Error().Err(err).Str("store", s.media.Describe()).Msg("store resume")
		c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "could not store file"})
		return
	}
	r, err := s.store.CreateResume(ctx, db.CreateResumeParams{
		UserID: u.ID, Filename: truncate(filepath.Base(fh.Filename), 255), StoragePath: key,
		MimeType: mime, SizeBytes: int64(len(data)),
	})
	if err != nil {
		_ = s.media.Delete(context.Background(), key)
		dbError(c, err)
		return
	}
	c.JSON(http.StatusCreated, toResumeDTO(r))
}

func (s *Server) deleteResume(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	u, _ := md.CurrentUser(c)
	ctx := c.Request.Context()
	r, err := s.store.DeleteResume(ctx, db.DeleteResumeParams{ID: id, UserID: u.ID})
	if err != nil {
		dbError(c, err)
		return
	}
	if err := s.media.Delete(ctx, r.StoragePath); err != nil {
		log.Warn().Err(err).Str("key", r.StoragePath).Msg("resume file not removed")
	}
	c.Status(http.StatusNoContent)
}

// downloadResume streams a resume to its owner or to a consultant. Clients
// never reach this route: a candidate's documents are presented to them by
// the consultant handling the search.
func (s *Server) downloadResume(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	u, _ := md.CurrentUser(c)
	ctx := c.Request.Context()
	r, err := s.store.GetResume(ctx, id)
	if err != nil {
		dbError(c, err)
		return
	}
	if r.UserID != u.ID && u.Role != "admin" {
		// Not "forbidden": whether this id exists is not the caller's business.
		c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	obj, err := s.media.Get(ctx, r.StoragePath)
	if errors.Is(err, storage.ErrNotFound) {
		c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "the stored file is missing"})
		return
	}
	if err != nil {
		log.Error().Err(err).Str("key", r.StoragePath).Msg("read resume")
		c.AbortWithStatusJSON(http.StatusBadGateway, gin.H{"error": "could not read file"})
		return
	}
	defer obj.Body.Close()

	if u.Role == "admin" && r.UserID != u.ID {
		s.audit(c, "download", "resume", strconv.FormatInt(r.ID, 10), gin.H{"candidate": r.UserID.String()})
	}
	h := c.Writer.Header()
	h.Set("Content-Type", r.MimeType)
	h.Set("Content-Length", strconv.FormatInt(obj.Size, 10))
	// Confidential: never cached by a proxy, never rendered inline as a page.
	h.Set("Cache-Control", "private, no-store")
	h.Set("Content-Disposition", "attachment; filename*=UTF-8''"+url.PathEscape(r.Filename))
	h.Set("Content-Security-Policy", "default-src 'none'; sandbox")
	c.Status(http.StatusOK)
	_, _ = io.Copy(c.Writer, obj.Body)
}
