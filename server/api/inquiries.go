// Consultation requests. The web site's Contact page is an email address;
// this is its app equivalent, and the one thing in the recruitment API that
// does not need an account.
package api

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	"github.com/rs/zerolog/log"
)

const maxMessageBytes = 5000

// hourlyInquiriesPerEmail stops a form from being submitted over and over
// with the same address; middleware.RateLimit covers the per-IP case.
const hourlyInquiriesPerEmail = 5

type inquiryDTO struct {
	ID           int64      `json:"id"`
	Kind         string     `json:"kind"`
	Name         string     `json:"name"`
	Email        string     `json:"email"`
	Phone        string     `json:"phone"`
	Company      string     `json:"company"`
	Office       string     `json:"office"`
	Message      string     `json:"message"`
	Status       string     `json:"status"`
	HandledAt    *time.Time `json:"handledAt"`
	CreatedAt    time.Time  `json:"createdAt"`
	AccountEmail string     `json:"accountEmail,omitempty"`
}

func toInquiryDTO(i db.Inquiry) inquiryDTO {
	return inquiryDTO{
		ID: i.ID, Kind: i.Kind, Name: i.Name, Email: i.Email, Phone: i.Phone,
		Company: i.Company, Office: i.Office, Message: i.Message, Status: i.Status,
		HandledAt: i.HandledAt, CreatedAt: i.CreatedAt,
	}
}

// createInquiry is public: someone who has not signed up can still ask for a
// consultation. When a signed-in caller sends one, the account is recorded.
func (s *Server) createInquiry(c *gin.Context) {
	var in struct {
		Kind    string `json:"kind"`
		Name    string `json:"name"`
		Email   string `json:"email"`
		Phone   string `json:"phone"`
		Company string `json:"company"`
		Office  string `json:"office"`
		Message string `json:"message"`
	}
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	in.Name = cleanLine(in.Name)
	in.Email = strings.TrimSpace(in.Email)
	in.Phone = cleanLine(in.Phone)
	in.Company = cleanLine(in.Company)
	in.Message = strings.TrimSpace(in.Message)
	switch {
	case !contains(inquiryKinds, in.Kind):
		badRequest(c, "kind must be 'hiring', 'career' or 'general'")
		return
	case in.Name == "":
		badRequest(c, "your name is required")
		return
	case !validEmail(in.Email):
		badRequest(c, "a valid email address is required")
		return
	case in.Message == "":
		badRequest(c, "please tell us what you would like to discuss")
		return
	case len(in.Message) > maxMessageBytes:
		badRequest(c, "message is too long")
		return
	case in.Office != "" && !contains(offices, in.Office):
		badRequest(c, "office must be 'tokyo' or 'singapore'")
		return
	}

	ctx := c.Request.Context()
	recent, err := s.store.CountRecentInquiriesFromIP(ctx, in.Email)
	if err != nil {
		dbError(c, err)
		return
	}
	if recent >= hourlyInquiriesPerEmail {
		c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
			"error": "we already have your recent messages and will be in touch",
		})
		return
	}

	i, err := s.store.CreateInquiry(ctx, db.CreateInquiryParams{
		UserID: currentUserID(c), Kind: in.Kind, Name: in.Name, Email: in.Email,
		Phone: in.Phone, Company: in.Company, Office: in.Office, Message: in.Message,
	})
	if err != nil {
		dbError(c, err)
		return
	}
	// Until a mailer is wired up, the log is where a consultant is alerted.
	log.Info().Str("kind", i.Kind).Str("office", i.Office).Int64("id", i.ID).Msg("consultation request")
	c.JSON(http.StatusCreated, toInquiryDTO(i))
}

// listMyInquiries lets a signed-in user see what they have sent us.
func (s *Server) listMyInquiries(c *gin.Context) {
	rows, err := s.store.ListInquiriesForUser(c.Request.Context(), currentUserID(c))
	if err != nil {
		dbError(c, err)
		return
	}
	out := make([]inquiryDTO, len(rows))
	for i, r := range rows {
		out[i] = toInquiryDTO(r)
	}
	c.JSON(http.StatusOK, out)
}

// ---- consultant side ---------------------------------------------------

var inquiryStates = []string{"new", "in_progress", "closed"}

func (s *Server) listInquiries(c *gin.Context) {
	status := c.Query("status")
	if status != "" && !contains(inquiryStates, status) {
		badRequest(c, "unknown status")
		return
	}
	limit, offset := pageParams(c, 50, 200)
	ctx := c.Request.Context()
	rows, err := s.store.ListInquiries(ctx, db.ListInquiriesParams{Status: status, Lim: limit, Off: offset})
	if err != nil {
		dbError(c, err)
		return
	}
	counts, err := s.store.CountInquiriesByStatus(ctx)
	if err != nil {
		dbError(c, err)
		return
	}
	byStatus := map[string]int64{}
	for _, row := range counts {
		byStatus[row.Status] = row.Total
	}
	out := make([]inquiryDTO, len(rows))
	for i, row := range rows {
		d := toInquiryDTO(row.Inquiry)
		d.AccountEmail = row.AccountEmail
		out[i] = d
	}
	c.JSON(http.StatusOK, gin.H{"inquiries": out, "countsByStatus": byStatus, "limit": limit, "offset": offset})
}

func (s *Server) setInquiryStatus(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	var in struct {
		Status string `json:"status"`
	}
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	if !contains(inquiryStates, in.Status) {
		badRequest(c, "status must be 'new', 'in_progress' or 'closed'")
		return
	}
	i, err := s.store.SetInquiryStatus(c.Request.Context(), db.SetInquiryStatusParams{
		ID: id, Status: in.Status, HandledBy: currentUserID(c),
	})
	if err != nil {
		dbError(c, err)
		return
	}
	s.audit(c, "status", "inquiry", strconv.FormatInt(id, 10), gin.H{"status": i.Status})
	c.JSON(http.StatusOK, toInquiryDTO(i))
}
