package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	md "github.com/mstoews/azma-associates/server/middleware"
	"github.com/rs/zerolog/log"
)

func requestLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		ev := log.Info()
		if c.Writer.Status() >= 500 {
			ev = log.Error()
		}
		ev.Str("method", c.Request.Method).
			Str("path", c.Request.URL.Path).
			Int("status", c.Writer.Status()).
			Dur("took", time.Since(start)).
			Msg("request")
	}
}

func badRequest(c *gin.Context, msg string) {
	c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": msg})
}

// dbError maps database errors to HTTP responses. Anything unexpected is
// logged and reported as a 500 without leaking SQL detail to the client.
func dbError(c *gin.Context, err error) {
	if errors.Is(err, pgx.ErrNoRows) {
		c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		switch pgErr.Code {
		case "23505": // unique_violation
			msg := "a record with that value already exists"
			switch {
			case strings.Contains(pgErr.ConstraintName, "slug"):
				msg = "that slug is already in use"
			case strings.Contains(pgErr.ConstraintName, "email"):
				msg = "a user with that email already exists"
			}
			c.AbortWithStatusJSON(http.StatusConflict, gin.H{"error": msg})
			return
		case "23514", "23503": // check_violation, foreign_key_violation
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": "invalid value: " + pgErr.ConstraintName})
			return
		}
	}
	log.Error().Err(err).Str("path", c.Request.URL.Path).Msg("database error")
	c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
}

func parseInt64Param(c *gin.Context, name string) (int64, bool) {
	id, err := strconv.ParseInt(c.Param(name), 10, 64)
	if err != nil || id <= 0 {
		badRequest(c, "invalid "+name)
		return 0, false
	}
	return id, true
}

func parseUUIDParam(c *gin.Context, name string) (uuid.UUID, bool) {
	id, err := uuid.Parse(c.Param(name))
	if err != nil {
		badRequest(c, "invalid "+name)
		return uuid.UUID{}, false
	}
	return id, true
}

func currentUserID(c *gin.Context) uuid.NullUUID {
	if u, ok := md.CurrentUser(c); ok {
		return uuid.NullUUID{UUID: u.ID, Valid: true}
	}
	return uuid.NullUUID{}
}

// audit records an admin action. A failed audit write is logged, not
// surfaced: the change itself has already been committed.
func (s *Server) audit(c *gin.Context, action, entity, entityID string, details any) {
	s.auditAs(c.Request.Context(), c, action, entity, entityID, details)
}

func (s *Server) auditAs(ctx context.Context, c *gin.Context, action, entity, entityID string, details any) {
	var uid uuid.NullUUID
	email := ""
	if u, ok := md.CurrentUser(c); ok {
		uid = uuid.NullUUID{UUID: u.ID, Valid: true}
		email = u.Email
	}
	if details == nil {
		details = map[string]any{}
	}
	raw, err := json.Marshal(details)
	if err != nil {
		raw = []byte(`{}`)
	}
	if err := s.store.InsertAudit(ctx, db.InsertAuditParams{
		UserID: uid, UserEmail: email, Action: action, Entity: entity, EntityID: entityID, Details: raw,
	}); err != nil {
		log.Error().Err(err).Str("action", action).Str("entity", entity).Msg("audit write failed")
	}
}

var nonSlug = regexp.MustCompile(`[^a-z0-9]+`)

// Slugify mirrors slugify() in src/app/site-data.ts so seeded URLs match the
// ones the static site used.
func Slugify(s string) string {
	s = strings.ToLower(s)
	s = strings.ReplaceAll(s, "&", " ")
	s = nonSlug.ReplaceAllString(s, "-")
	return strings.Trim(s, "-")
}

var slugRe = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)

// reservedSlugs are top-level paths the front end or this server already owns.
var reservedSlugs = map[string]bool{
	"admin": true, "api": true, "profile": true, "media": true, "wp-content": true, "healthz": true,
}

func validSlug(slug string, topLevel bool) string {
	if slug == "" {
		return "slug is required (titles without Latin letters need an explicit slug)"
	}
	if len(slug) > 120 || !slugRe.MatchString(slug) {
		return "slug may contain only lowercase letters, digits and single hyphens"
	}
	if topLevel && reservedSlugs[slug] {
		return "slug '" + slug + "' is reserved"
	}
	return ""
}

// validAssetURL accepts site-relative paths and http(s) URLs. It exists to
// keep javascript: and data: URLs out of image src attributes.
func validAssetURL(u string) bool {
	if u == "" {
		return true
	}
	if strings.HasPrefix(u, "/") && !strings.HasPrefix(u, "//") {
		return true
	}
	return strings.HasPrefix(u, "https://") || strings.HasPrefix(u, "http://")
}

func validLinkURL(u string) bool {
	return validAssetURL(u) || strings.HasPrefix(u, "mailto:") || strings.HasPrefix(u, "tel:")
}

func int4Ptr(v pgtype.Int4) *int32 {
	if !v.Valid {
		return nil
	}
	return &v.Int32
}
