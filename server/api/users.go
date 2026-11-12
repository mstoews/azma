package api

import (
	"encoding/json"
	"net/http"
	"net/mail"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	md "github.com/mstoews/azma-associates/server/middleware"
	"github.com/rs/zerolog/log"
)

func (s *Server) listUsers(c *gin.Context) {
	rows, err := s.store.ListUsers(c.Request.Context())
	if err != nil {
		dbError(c, err)
		return
	}
	out := make([]userDTO, len(rows))
	for i, u := range rows {
		out[i] = toUserDTO(u)
	}
	c.JSON(http.StatusOK, out)
}

func (s *Server) createUser(c *gin.Context) {
	var in struct {
		Email    string `json:"email"`
		Name     string `json:"name"`
		Password string `json:"password"`
	}
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	in.Email = strings.TrimSpace(in.Email)
	if addr, err := mail.ParseAddress(in.Email); err != nil || addr.Address != in.Email {
		badRequest(c, "a valid email address is required")
		return
	}
	hash, err := HashPassword(in.Password)
	if err != nil {
		badRequest(c, err.Error())
		return
	}
	u, err := s.store.CreateUser(c.Request.Context(), db.CreateUserParams{
		Email: in.Email, Name: strings.TrimSpace(in.Name), PasswordHash: hash,
	})
	if err != nil {
		dbError(c, err)
		return
	}
	s.audit(c, "create", "user", u.ID.String(), gin.H{"email": u.Email})
	c.JSON(http.StatusCreated, toUserDTO(u))
}

// guardLastAdmin refuses changes that would leave nobody able to sign in.
func (s *Server) guardLastAdmin(c *gin.Context, target db.User) bool {
	if target.Disabled {
		return true // already not counted
	}
	n, err := s.store.CountActiveAdmins(c.Request.Context())
	if err != nil {
		dbError(c, err)
		return false
	}
	if n <= 1 {
		c.AbortWithStatusJSON(http.StatusConflict, gin.H{"error": "cannot remove the last active administrator"})
		return false
	}
	return true
}

func (s *Server) updateUser(c *gin.Context) {
	id, ok := parseUUIDParam(c, "id")
	if !ok {
		return
	}
	var in struct {
		Name     string `json:"name"`
		Disabled bool   `json:"disabled"`
	}
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	ctx := c.Request.Context()
	target, err := s.store.GetUser(ctx, id)
	if err != nil {
		dbError(c, err)
		return
	}
	if in.Disabled && !target.Disabled {
		if self, _ := md.CurrentUser(c); self.ID == id {
			badRequest(c, "you cannot disable your own account")
			return
		}
		if !s.guardLastAdmin(c, target) {
			return
		}
	}
	u, err := s.store.UpdateUser(ctx, db.UpdateUserParams{ID: id, Name: strings.TrimSpace(in.Name), Disabled: in.Disabled})
	if err != nil {
		dbError(c, err)
		return
	}
	if u.Disabled {
		if err := s.store.RevokeUserSessions(ctx, id); err != nil {
			log.Error().Err(err).Msg("revoke sessions of disabled user")
		}
	}
	s.audit(c, "update", "user", id.String(), gin.H{"name": u.Name, "disabled": u.Disabled})
	c.JSON(http.StatusOK, toUserDTO(u))
}

// setUserPassword is an administrator resetting someone's password. It also
// clears any lockout and signs that user out everywhere.
func (s *Server) setUserPassword(c *gin.Context) {
	id, ok := parseUUIDParam(c, "id")
	if !ok {
		return
	}
	var in struct {
		Password string `json:"password"`
	}
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	hash, err := HashPassword(in.Password)
	if err != nil {
		badRequest(c, err.Error())
		return
	}
	ctx := c.Request.Context()
	if _, err := s.store.GetUser(ctx, id); err != nil {
		dbError(c, err)
		return
	}
	if err := s.store.SetUserPassword(ctx, db.SetUserPasswordParams{ID: id, PasswordHash: hash}); err != nil {
		dbError(c, err)
		return
	}
	if self, _ := md.CurrentUser(c); self.ID != id {
		if err := s.store.RevokeUserSessions(ctx, id); err != nil {
			log.Error().Err(err).Msg("revoke sessions after password reset")
		}
	}
	s.audit(c, "password_reset", "user", id.String(), nil)
	c.Status(http.StatusNoContent)
}

func (s *Server) deleteUser(c *gin.Context) {
	id, ok := parseUUIDParam(c, "id")
	if !ok {
		return
	}
	if self, _ := md.CurrentUser(c); self.ID == id {
		badRequest(c, "you cannot delete your own account")
		return
	}
	ctx := c.Request.Context()
	target, err := s.store.GetUser(ctx, id)
	if err != nil {
		dbError(c, err)
		return
	}
	if !s.guardLastAdmin(c, target) {
		return
	}
	if err := s.store.DeleteUser(ctx, id); err != nil {
		dbError(c, err)
		return
	}
	s.audit(c, "delete", "user", id.String(), gin.H{"email": target.Email})
	c.Status(http.StatusNoContent)
}

// ---- audit -------------------------------------------------------------

type auditDTO struct {
	ID        int64     `json:"id"`
	UserEmail string    `json:"userEmail"`
	Action    string    `json:"action"`
	Entity    string    `json:"entity"`
	EntityID  string    `json:"entityId"`
	Details   any       `json:"details,omitempty"`
	CreatedAt time.Time `json:"createdAt"`
	UserID    *string   `json:"userId"`
}

func (s *Server) listAudit(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	withDetails := c.Query("details") == "1"
	rows, err := s.store.ListAudit(c.Request.Context(), db.ListAuditParams{Lim: int32(limit), Off: int32(offset)})
	if err != nil {
		dbError(c, err)
		return
	}
	out := make([]auditDTO, len(rows))
	for i, r := range rows {
		d := auditDTO{ID: r.ID, UserEmail: r.UserEmail, Action: r.Action, Entity: r.Entity,
			EntityID: r.EntityID, CreatedAt: r.CreatedAt}
		if r.UserID.Valid {
			id := r.UserID.UUID.String()
			d.UserID = &id
		}
		if withDetails {
			d.Details = json.RawMessage(r.Details)
		}
		out[i] = d
	}
	c.JSON(http.StatusOK, out)
}
