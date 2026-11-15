// Applications: a candidate putting themselves forward for a position, and
// the two views of that application — the candidate's own, and the one a
// client or consultant works from.
//
// How much of a candidate a client sees is deliberate. Until a consultant has
// presented them (the application reaches `shortlisted`), the client sees the
// professional summary but not the person's name, contact details or resume.
// That mirrors the firm's own search process: we longlist, assess, and then
// present a shortlist.
package api

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	md "github.com/mstoews/azma-associates/server/middleware"
)

const maxCoverNoteBytes = 4000

// presentedStates are the states in which the candidate has been put in front
// of the client, so the client may see who they are.
var presentedStates = []string{"shortlisted", "interviewing", "offer", "placed"}

// employerSettableStates are the decisions a client makes on their own. Moving
// an application to `shortlisted` is the consultant's call, because that is
// what releases the candidate's details.
var employerSettableStates = []string{"under_review", "interviewing", "offer", "placed", "rejected"}

// ---- the candidate's view ----------------------------------------------

type applicationDTO struct {
	ID             int64     `json:"id"`
	JobID          int64     `json:"jobId"`
	JobTitle       string    `json:"jobTitle"`
	JobCompany     string    `json:"jobCompany"`
	JobLocation    string    `json:"jobLocation"`
	JobStatus      string    `json:"jobStatus"`
	Status         string    `json:"status"`
	CoverNote      string    `json:"coverNote"`
	ResumeFilename string    `json:"resumeFilename"`
	CreatedAt      time.Time `json:"createdAt"`
	UpdatedAt      time.Time `json:"updatedAt"`
}

func toCandidateApplicationDTO(row db.ListApplicationsForCandidateRow) applicationDTO {
	company := row.JobCompany
	if row.JobConfidential {
		company = confidentialLabel
	}
	a := row.JobApplication
	return applicationDTO{
		ID: a.ID, JobID: a.JobID, JobTitle: row.JobTitle, JobCompany: company,
		JobLocation: row.JobLocation, JobStatus: row.JobStatus, Status: a.Status,
		CoverNote: a.CoverNote, ResumeFilename: row.ResumeFilename,
		CreatedAt: a.CreatedAt, UpdatedAt: a.UpdatedAt,
	}
}

// ---- the client's and consultant's view --------------------------------

type applicantDTO struct {
	ID        int64     `json:"id"`
	JobID     int64     `json:"jobId"`
	Status    string    `json:"status"`
	CoverNote string    `json:"coverNote"`
	CreatedAt time.Time `json:"createdAt"`

	Headline        string `json:"headline"`
	Location        string `json:"location"`
	CurrentEmployer string `json:"currentEmployer"`
	CurrentTitle    string `json:"currentTitle"`
	YearsExperience int32  `json:"yearsExperience"`

	// Released to a client only once the candidate has been presented;
	// a consultant always sees them.
	Name        string `json:"name"`
	Email       string `json:"email"`
	ResumeID    *int64 `json:"resumeId"`
	Resume      string `json:"resumeFilename"`
	DownloadURL string `json:"resumeDownloadUrl,omitempty"`
	// Presented says whether the identity above is filled in.
	Presented bool `json:"presented"`
}

func toApplicantDTO(row db.ListApplicationsForJobRow, full bool) applicantDTO {
	a := row.JobApplication
	d := applicantDTO{
		ID: a.ID, JobID: a.JobID, Status: a.Status, CoverNote: a.CoverNote, CreatedAt: a.CreatedAt,
		Headline: row.CandidateHeadline, Location: row.CandidateLocation,
		CurrentEmployer: row.CandidateEmployer, CurrentTitle: row.CandidateTitle,
		YearsExperience: row.CandidateYears,
		Presented:       full || contains(presentedStates, a.Status),
	}
	if !d.Presented {
		return d
	}
	d.Name = row.CandidateName
	d.Email = row.CandidateEmail
	d.Resume = row.ResumeFilename
	if a.ResumeID.Valid {
		id := a.ResumeID.Int64
		d.ResumeID = &id
		// Only a consultant downloads the document itself.
		if full {
			d.DownloadURL = "/api/v1/resumes/" + strconv.FormatInt(id, 10) + "/file"
		}
	}
	return d
}

// ---- applying ----------------------------------------------------------

func (s *Server) createApplication(c *gin.Context) {
	var in struct {
		JobID     int64  `json:"jobId"`
		ResumeID  *int64 `json:"resumeId"`
		CoverNote string `json:"coverNote"`
	}
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	in.CoverNote = strings.TrimSpace(in.CoverNote)
	if in.JobID <= 0 {
		badRequest(c, "jobId is required")
		return
	}
	if len(in.CoverNote) > maxCoverNoteBytes {
		badRequest(c, "your note is too long")
		return
	}
	u, _ := md.CurrentUser(c)
	ctx := c.Request.Context()

	if _, err := s.store.GetPublishedJob(ctx, in.JobID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			badRequest(c, "that position is no longer open")
			return
		}
		dbError(c, err)
		return
	}

	// A resume is what the consultant actually works from. Default to the most
	// recent one when the app does not name one.
	resumes, err := s.store.ListResumes(ctx, u.ID)
	if err != nil {
		dbError(c, err)
		return
	}
	if len(resumes) == 0 {
		badRequest(c, "upload your resume before applying")
		return
	}
	chosen := resumes[0]
	if in.ResumeID != nil {
		found := false
		for _, r := range resumes {
			if r.ID == *in.ResumeID {
				chosen, found = r, true
				break
			}
		}
		if !found {
			badRequest(c, "that resume is not on your account")
			return
		}
	}

	a, err := s.store.CreateApplication(ctx, db.CreateApplicationParams{
		JobID: in.JobID, CandidateID: u.ID,
		ResumeID:  pgtype.Int8{Int64: chosen.ID, Valid: true},
		CoverNote: in.CoverNote,
	})
	if err != nil {
		if isUniqueViolation(err) {
			c.AbortWithStatusJSON(http.StatusConflict, gin.H{"error": "you have already applied for this position"})
			return
		}
		dbError(c, err)
		return
	}
	c.JSON(http.StatusCreated, gin.H{"id": a.ID, "status": a.Status, "createdAt": a.CreatedAt})
}

func (s *Server) withdrawApplication(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	u, _ := md.CurrentUser(c)
	a, err := s.store.WithdrawApplication(c.Request.Context(), db.WithdrawApplicationParams{
		ID: id, CandidateID: u.ID,
	})
	if err != nil {
		dbError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"id": a.ID, "status": a.Status})
}

// ---- saved positions ---------------------------------------------------

func (s *Server) saveJob(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	u, _ := md.CurrentUser(c)
	ctx := c.Request.Context()
	if _, err := s.store.GetPublishedJob(ctx, id); err != nil {
		dbError(c, err)
		return
	}
	if err := s.store.SaveJob(ctx, db.SaveJobParams{CandidateID: u.ID, JobID: id}); err != nil {
		dbError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (s *Server) unsaveJob(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	u, _ := md.CurrentUser(c)
	if err := s.store.UnsaveJob(c.Request.Context(), db.UnsaveJobParams{CandidateID: u.ID, JobID: id}); err != nil {
		dbError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

// ---- reviewing applicants ----------------------------------------------

// listJobApplicants serves both the client (their own posting, redacted until
// a candidate is presented) and the consultant (any posting, in full).
func (s *Server) listJobApplicants(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	u, _ := md.CurrentUser(c)
	ctx := c.Request.Context()
	job, err := s.store.GetJob(ctx, id)
	if err != nil {
		dbError(c, err)
		return
	}
	full := u.Role == "admin"
	if !full && job.EmployerID != u.ID {
		c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	rows, err := s.store.ListApplicationsForJob(ctx, id)
	if err != nil {
		dbError(c, err)
		return
	}
	out := make([]applicantDTO, len(rows))
	for i, row := range rows {
		out[i] = toApplicantDTO(row, full)
	}
	c.JSON(http.StatusOK, gin.H{"job": toJobDTO(job), "applicants": out})
}

// setApplicationStatus is a client's decision on a candidate, or a
// consultant's. Only a consultant can move one to `shortlisted`, which is
// what releases the candidate's details to the client.
func (s *Server) setApplicationStatus(c *gin.Context) {
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
	u, _ := md.CurrentUser(c)
	ctx := c.Request.Context()
	a, err := s.store.GetApplication(ctx, id)
	if err != nil {
		dbError(c, err)
		return
	}
	if u.Role == "admin" {
		if !contains(applicationStates, in.Status) {
			badRequest(c, "unknown status")
			return
		}
	} else {
		job, err := s.store.GetJob(ctx, a.JobID)
		if err != nil {
			dbError(c, err)
			return
		}
		if job.EmployerID != u.ID {
			c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}
		if !contains(employerSettableStates, in.Status) {
			badRequest(c, "a consultant shortlists candidates; you can record review, interview, offer, placement or a decline")
			return
		}
	}
	if a.Status == "withdrawn" {
		c.AbortWithStatusJSON(http.StatusConflict, gin.H{"error": "the candidate has withdrawn this application"})
		return
	}
	updated, err := s.store.SetApplicationStatus(ctx, db.SetApplicationStatusParams{ID: id, Status: in.Status})
	if err != nil {
		dbError(c, err)
		return
	}
	if u.Role == "admin" {
		s.audit(c, "status", "application", strconv.FormatInt(id, 10), gin.H{"status": updated.Status})
	}
	c.JSON(http.StatusOK, gin.H{"id": updated.ID, "status": updated.Status, "updatedAt": updated.UpdatedAt})
}
