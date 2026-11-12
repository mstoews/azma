package api

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	md "github.com/mstoews/azma-associates/server/middleware"
	"github.com/rs/zerolog/log"
	"golang.org/x/crypto/bcrypt"
)

const (
	MinPasswordLength = 12
	bcryptCost        = 12
)

// dummyHash is compared against when the email is unknown so that a miss
// costs the same as a wrong password and response time does not reveal
// which emails have accounts.
var dummyHash, _ = bcrypt.GenerateFromPassword([]byte("not-a-real-password-placeholder"), bcryptCost)

func HashPassword(pw string) (string, error) {
	if msg := PasswordProblem(pw); msg != "" {
		return "", errors.New(msg)
	}
	h, err := bcrypt.GenerateFromPassword([]byte(pw), bcryptCost)
	return string(h), err
}

// PasswordProblem returns a user-facing reason a password is unacceptable, or "".
func PasswordProblem(pw string) string {
	if len(pw) < MinPasswordLength {
		return "password must be at least 12 characters"
	}
	if len(pw) > 72 { // bcrypt ignores bytes past 72
		return "password must be at most 72 bytes"
	}
	return ""
}

type userDTO struct {
	ID          string     `json:"id"`
	Email       string     `json:"email"`
	Name        string     `json:"name"`
	Role        string     `json:"role"`
	Disabled    bool       `json:"disabled"`
	LockedUntil *time.Time `json:"lockedUntil"`
	LastLoginAt *time.Time `json:"lastLoginAt"`
	CreatedAt   time.Time  `json:"createdAt"`
}

func toUserDTO(u db.User) userDTO {
	return userDTO{u.ID.String(), u.Email, u.Name, u.Role, u.Disabled, u.LockedUntil, u.LastLoginAt, u.CreatedAt}
}

func newToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func (s *Server) login(c *gin.Context) {
	var in struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := c.ShouldBindJSON(&in); err != nil || in.Email == "" || in.Password == "" {
		badRequest(c, "email and password are required")
		return
	}
	ctx := c.Request.Context()
	invalid := func() {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid email or password"})
	}

	user, err := s.store.GetUserByEmail(ctx, strings.TrimSpace(in.Email))
	if err != nil {
		if !errors.Is(err, pgx.ErrNoRows) {
			dbError(c, err)
			return
		}
		_ = bcrypt.CompareHashAndPassword(dummyHash, []byte(in.Password))
		invalid()
		return
	}
	if user.LockedUntil != nil && user.LockedUntil.After(s.now()) {
		_ = bcrypt.CompareHashAndPassword(dummyHash, []byte(in.Password))
		c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
			"error": "too many failed attempts; try again later",
		})
		return
	}
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(in.Password)); err != nil {
		if _, err := s.store.RecordLoginFailure(ctx, db.RecordLoginFailureParams{
			ID:            user.ID,
			Threshold:     int32(s.config.LoginLockoutThreshold),
			WindowSeconds: s.config.LoginLockoutWindow.Seconds(),
		}); err != nil {
			log.Error().Err(err).Msg("record login failure")
		}
		invalid()
		return
	}
	// Checked after the password so a disabled account is not discoverable
	// by guessing.
	if user.Disabled || user.Role != "admin" {
		invalid()
		return
	}

	token, err := newToken()
	if err != nil {
		dbError(c, err)
		return
	}
	expires := s.now().Add(s.config.SessionDuration)
	if _, err := s.store.CreateSession(ctx, db.CreateSessionParams{
		UserID: user.ID, TokenHash: md.HashToken(token), ExpiresAt: expires,
		UserAgent: truncate(c.Request.UserAgent(), 300), Ip: c.ClientIP(),
	}); err != nil {
		dbError(c, err)
		return
	}
	if err := s.store.RecordLoginSuccess(ctx, user.ID); err != nil {
		log.Error().Err(err).Msg("record login success")
	}
	md.SetUser(c, user) // so the audit row names who logged in
	s.audit(c, "login", "user", user.ID.String(), gin.H{"ip": c.ClientIP()})
	c.JSON(http.StatusOK, gin.H{"token": token, "expiresAt": expires, "user": toUserDTO(user)})
}

func (s *Server) logout(c *gin.Context) {
	sess, _ := md.CurrentSession(c)
	if err := s.store.RevokeSession(c.Request.Context(), sess.ID); err != nil {
		dbError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (s *Server) me(c *gin.Context) {
	u, _ := md.CurrentUser(c)
	sess, _ := md.CurrentSession(c)
	c.JSON(http.StatusOK, gin.H{"user": toUserDTO(u), "expiresAt": sess.ExpiresAt})
}

func (s *Server) changeOwnPassword(c *gin.Context) {
	var in struct {
		CurrentPassword string `json:"currentPassword"`
		NewPassword     string `json:"newPassword"`
	}
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	u, _ := md.CurrentUser(c)
	sess, _ := md.CurrentSession(c)
	if bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(in.CurrentPassword)) != nil {
		c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "current password is incorrect"})
		return
	}
	hash, err := HashPassword(in.NewPassword)
	if err != nil {
		badRequest(c, err.Error())
		return
	}
	ctx := c.Request.Context()
	if err := s.store.SetUserPassword(ctx, db.SetUserPasswordParams{ID: u.ID, PasswordHash: hash}); err != nil {
		dbError(c, err)
		return
	}
	// Sign out every other device; keep this one.
	if err := s.store.RevokeOtherUserSessions(ctx, db.RevokeOtherUserSessionsParams{UserID: u.ID, KeepID: sess.ID}); err != nil {
		log.Error().Err(err).Msg("revoke other sessions")
	}
	s.audit(c, "password", "user", u.ID.String(), nil)
	c.Status(http.StatusNoContent)
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}
