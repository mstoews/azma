// Package middleware holds the Gin middleware for session authentication and
// admin authorization.
package middleware

import (
	"context"
	"crypto/sha256"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	"github.com/rs/zerolog/log"
)

const (
	sessionKey = "cms.session"
	userKey    = "cms.user"
)

// touchInterval throttles last_used_at writes so a burst of admin requests
// does not turn into a burst of UPDATEs.
const touchInterval = time.Minute

// HashToken is the one place a bearer token is turned into its stored form.
func HashToken(token string) []byte {
	h := sha256.Sum256([]byte(token))
	return h[:]
}

// BearerToken extracts the token from "Authorization: Bearer <token>".
func BearerToken(c *gin.Context) string {
	h := c.GetHeader("Authorization")
	const prefix = "Bearer "
	if len(h) <= len(prefix) || !strings.EqualFold(h[:len(prefix)], prefix) {
		return ""
	}
	return strings.TrimSpace(h[len(prefix):])
}

// AuthSession requires a live session. The SQL lookup itself rejects revoked
// and expired sessions and disabled users, so a row coming back means the
// caller is authenticated.
func AuthSession(store db.Store) gin.HandlerFunc {
	return func(c *gin.Context) {
		token := BearerToken(c)
		if token == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
			return
		}
		row, err := store.GetSessionUser(c.Request.Context(), HashToken(token))
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "session invalid or expired"})
				return
			}
			log.Error().Err(err).Msg("session lookup failed")
			c.AbortWithStatusJSON(http.StatusServiceUnavailable, gin.H{"error": "authentication unavailable"})
			return
		}
		if time.Since(row.Session.LastUsedAt) > touchInterval {
			id := row.Session.ID
			go func() {
				ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
				defer cancel()
				_ = store.TouchSession(ctx, id)
			}()
		}
		c.Set(sessionKey, row.Session)
		c.Set(userKey, row.User)
		c.Next()
	}
}

// RequireAdmin must run after AuthSession.
func RequireAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		u, ok := CurrentUser(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
			return
		}
		if u.Role != "admin" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "administrator access required"})
			return
		}
		c.Next()
	}
}

func CurrentUser(c *gin.Context) (db.User, bool) {
	v, ok := c.Get(userKey)
	if !ok {
		return db.User{}, false
	}
	u, ok := v.(db.User)
	return u, ok
}

// SetUser records the acting user, for handlers (login) that establish
// identity themselves rather than through AuthSession.
func SetUser(c *gin.Context, u db.User) { c.Set(userKey, u) }

func CurrentSession(c *gin.Context) (db.Session, bool) {
	v, ok := c.Get(sessionKey)
	if !ok {
		return db.Session{}, false
	}
	s, ok := v.(db.Session)
	return s, ok
}

// SecurityHeaders sets conservative defaults on every response.
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		h := c.Writer.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "strict-origin-when-cross-origin")
		h.Set("X-Frame-Options", "SAMEORIGIN")
		c.Next()
	}
}
