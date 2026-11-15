// Positions an employer has asked us to fill, and the public board they reach
// once a consultant has approved them.
package api

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgtype"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	md "github.com/mstoews/azma-associates/server/middleware"
)

const (
	maxJobTextBytes = 20000
	// confidentialLabel stands in for the client's name on the public board
	// when the search is confidential.
	confidentialLabel = "Confidential client"
)

type jobDTO struct {
	ID               int64      `json:"id"`
	Title            string     `json:"title"`
	Company          string     `json:"company"`
	Confidential     bool       `json:"confidential"`
	Location         string     `json:"location"`
	Remote           bool       `json:"remote"`
	Sector           string     `json:"sector"`
	EmploymentType   string     `json:"employmentType"`
	Description      string     `json:"description"`
	Requirements     string     `json:"requirements"`
	SalaryMin        *int32     `json:"salaryMin"`
	SalaryMax        *int32     `json:"salaryMax"`
	SalaryCurrency   string     `json:"salaryCurrency"`
	Status           string     `json:"status"`
	ReviewNote       string     `json:"reviewNote,omitempty"`
	PublishedAt      *time.Time `json:"publishedAt"`
	CreatedAt        time.Time  `json:"createdAt"`
	UpdatedAt        time.Time  `json:"updatedAt"`
	ApplicationCount *int64     `json:"applicationCount,omitempty"`
	EmployerEmail    string     `json:"employerEmail,omitempty"`
	EmployerCompany  string     `json:"employerCompany,omitempty"`
}

// toJobDTO is the owner's and the consultant's view: everything, including the
// client's name and any review note.
func toJobDTO(j db.Job) jobDTO {
	return jobDTO{
		ID: j.ID, Title: j.Title, Company: j.Company, Confidential: j.Confidential,
		Location: j.Location, Remote: j.Remote, Sector: j.Sector,
		EmploymentType: j.EmploymentType, Description: j.Description, Requirements: j.Requirements,
		SalaryMin: int4Ptr(j.SalaryMin), SalaryMax: int4Ptr(j.SalaryMax), SalaryCurrency: j.SalaryCurrency,
		Status: j.Status, ReviewNote: j.ReviewNote, PublishedAt: j.PublishedAt,
		CreatedAt: j.CreatedAt, UpdatedAt: j.UpdatedAt,
	}
}

// toPublicJobDTO is what a candidate sees. A confidential search is shown
// without the client's name, and a consultant's internal note never leaves
// the firm.
func toPublicJobDTO(j db.Job) jobDTO {
	d := toJobDTO(j)
	d.ReviewNote = ""
	if j.Confidential {
		d.Company = confidentialLabel
	}
	return d
}

// ---- public board ------------------------------------------------------

func (s *Server) listPublicJobs(c *gin.Context) {
	q := cleanLine(c.Query("q"))
	sector := cleanLine(c.Query("sector"))
	empType := cleanLine(c.Query("employmentType"))
	remoteOnly := c.Query("remote") == "1" || c.Query("remote") == "true"
	if sector != "" && !contains(sectors, sector) {
		badRequest(c, "unknown sector")
		return
	}
	if empType != "" && !contains(employmentTypes, empType) {
		badRequest(c, "unknown employmentType")
		return
	}
	limit, offset := pageParams(c, 25, 100)

	ctx := c.Request.Context()
	rows, err := s.store.ListPublishedJobs(ctx, db.ListPublishedJobsParams{
		Sector: sector, EmploymentType: empType, RemoteOnly: remoteOnly, Q: q,
		Lim: limit, Off: offset,
	})
	if err != nil {
		dbError(c, err)
		return
	}
	total, err := s.store.CountPublishedJobs(ctx, db.CountPublishedJobsParams{
		Sector: sector, EmploymentType: empType, RemoteOnly: remoteOnly, Q: q,
	})
	if err != nil {
		dbError(c, err)
		return
	}
	out := make([]jobDTO, len(rows))
	for i, j := range rows {
		out[i] = toPublicJobDTO(j)
	}
	c.JSON(http.StatusOK, gin.H{"jobs": out, "total": total, "limit": limit, "offset": offset})
}

func (s *Server) getPublicJob(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	j, err := s.store.GetPublishedJob(c.Request.Context(), id)
	if err != nil {
		dbError(c, err)
		return
	}
	c.JSON(http.StatusOK, toPublicJobDTO(j))
}

// pageParams reads limit/offset, clamped so a client cannot ask for the whole
// table in one request.
func pageParams(c *gin.Context, def, max int) (lim, off int32) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", strconv.Itoa(def)))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	if limit <= 0 || limit > max {
		limit = def
	}
	if offset < 0 {
		offset = 0
	}
	return int32(limit), int32(offset)
}

// ---- employer postings -------------------------------------------------

type jobInput struct {
	Title          string `json:"title"`
	Company        string `json:"company"`
	Confidential   bool   `json:"confidential"`
	Location       string `json:"location"`
	Remote         bool   `json:"remote"`
	Sector         string `json:"sector"`
	EmploymentType string `json:"employmentType"`
	Description    string `json:"description"`
	Requirements   string `json:"requirements"`
	SalaryMin      *int32 `json:"salaryMin"`
	SalaryMax      *int32 `json:"salaryMax"`
	SalaryCurrency string `json:"salaryCurrency"`
	// Submit sends the posting to a consultant for review; otherwise it is
	// saved as a draft only the employer can see.
	Submit bool `json:"submit"`
}

func (in *jobInput) normalize() string {
	in.Title = cleanLine(in.Title)
	in.Company = cleanLine(in.Company)
	in.Location = cleanLine(in.Location)
	in.Sector = cleanLine(in.Sector)
	in.SalaryCurrency = strings.ToUpper(cleanLine(in.SalaryCurrency))
	in.Description = strings.TrimSpace(in.Description)
	in.Requirements = strings.TrimSpace(in.Requirements)
	if in.EmploymentType == "" {
		in.EmploymentType = "full_time"
	}
	switch {
	case in.Title == "":
		return "title is required"
	case in.Company == "":
		return "company is required"
	case in.Sector != "" && !contains(sectors, in.Sector):
		return "unknown sector: " + in.Sector
	case !contains(employmentTypes, in.EmploymentType):
		return "unknown employment type"
	case in.SalaryCurrency != "" && !contains(currencies, in.SalaryCurrency):
		return "unsupported currency"
	case len(in.Description) > maxJobTextBytes || len(in.Requirements) > maxJobTextBytes:
		return "description or requirements is too long"
	case in.SalaryMin != nil && *in.SalaryMin < 0, in.SalaryMax != nil && *in.SalaryMax < 0:
		return "salary cannot be negative"
	case in.SalaryMin != nil && in.SalaryMax != nil && *in.SalaryMax < *in.SalaryMin:
		return "maximum salary is below the minimum"
	case (in.SalaryMin != nil || in.SalaryMax != nil) && in.SalaryCurrency == "":
		return "choose a currency for the salary range"
	}
	// A posting a consultant is asked to act on needs enough to act on.
	if in.Submit && len(in.Description) < 40 {
		return "please describe the position in at least a few sentences before submitting it"
	}
	return ""
}

func (in *jobInput) status() string {
	if in.Submit {
		return "pending"
	}
	return "draft"
}

func int4Of(v *int32) pgtype.Int4 {
	if v == nil {
		return pgtype.Int4{}
	}
	return pgtype.Int4{Int32: *v, Valid: true}
}

func (s *Server) createJob(c *gin.Context) {
	var in jobInput
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	if msg := in.normalize(); msg != "" {
		badRequest(c, msg)
		return
	}
	u, _ := md.CurrentUser(c)
	j, err := s.store.CreateJob(c.Request.Context(), db.CreateJobParams{
		EmployerID: u.ID, Title: in.Title, Company: in.Company, Confidential: in.Confidential,
		Location: in.Location, Remote: in.Remote, Sector: in.Sector,
		EmploymentType: in.EmploymentType, Description: in.Description, Requirements: in.Requirements,
		SalaryMin: int4Of(in.SalaryMin), SalaryMax: int4Of(in.SalaryMax),
		SalaryCurrency: in.SalaryCurrency, Status: in.status(),
	})
	if err != nil {
		dbError(c, err)
		return
	}
	c.JSON(http.StatusCreated, toJobDTO(j))
}

// updateJob edits a posting. An approved posting that is edited leaves the
// board and goes back to review, so what candidates see is always what a
// consultant signed off on.
func (s *Server) updateJob(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	var in jobInput
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	if msg := in.normalize(); msg != "" {
		badRequest(c, msg)
		return
	}
	u, _ := md.CurrentUser(c)
	j, err := s.store.UpdateJob(c.Request.Context(), db.UpdateJobParams{
		ID: id, EmployerID: u.ID, Title: in.Title, Company: in.Company, Confidential: in.Confidential,
		Location: in.Location, Remote: in.Remote, Sector: in.Sector,
		EmploymentType: in.EmploymentType, Description: in.Description, Requirements: in.Requirements,
		SalaryMin: int4Of(in.SalaryMin), SalaryMax: int4Of(in.SalaryMax),
		SalaryCurrency: in.SalaryCurrency, Status: in.status(),
	})
	if err != nil {
		dbError(c, err) // no row for this owner reads as 404
		return
	}
	c.JSON(http.StatusOK, toJobDTO(j))
}

// employerJobStatus covers the transitions an employer makes themselves.
var employerJobStates = []string{"draft", "pending", "filled", "closed"}

func (s *Server) setEmployerJobStatus(c *gin.Context) {
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
	if !contains(employerJobStates, in.Status) {
		badRequest(c, "status must be one of draft, pending, filled, closed")
		return
	}
	u, _ := md.CurrentUser(c)
	j, err := s.store.SetJobStatusForEmployer(c.Request.Context(), db.SetJobStatusForEmployerParams{
		ID: id, EmployerID: u.ID, Status: in.Status,
	})
	if err != nil {
		dbError(c, err)
		return
	}
	c.JSON(http.StatusOK, toJobDTO(j))
}

func (s *Server) deleteJob(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	u, _ := md.CurrentUser(c)
	if _, err := s.store.DeleteJob(c.Request.Context(), db.DeleteJobParams{ID: id, EmployerID: u.ID}); err != nil {
		dbError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

// ---- consultant review -------------------------------------------------

func (s *Server) listJobsForAdmin(c *gin.Context) {
	status := c.Query("status")
	if status != "" && !contains(jobStates, status) {
		badRequest(c, "unknown status")
		return
	}
	limit, offset := pageParams(c, 50, 200)
	ctx := c.Request.Context()
	rows, err := s.store.ListJobsForAdmin(ctx, db.ListJobsForAdminParams{Status: status, Lim: limit, Off: offset})
	if err != nil {
		dbError(c, err)
		return
	}
	counts, err := s.store.CountJobsByStatus(ctx)
	if err != nil {
		dbError(c, err)
		return
	}
	byStatus := map[string]int64{}
	for _, row := range counts {
		byStatus[row.Status] = row.Total
	}
	out := make([]jobDTO, len(rows))
	for i, row := range rows {
		d := toJobDTO(row.Job)
		n := row.ApplicationCount
		d.ApplicationCount = &n
		d.EmployerEmail = row.EmployerEmail
		d.EmployerCompany = row.EmployerCompany
		out[i] = d
	}
	c.JSON(http.StatusOK, gin.H{"jobs": out, "countsByStatus": byStatus, "limit": limit, "offset": offset})
}

// setJobStatus is a consultant's decision on a posting: publish it, send it
// back with a note, or take it down.
func (s *Server) setJobStatus(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	var in struct {
		Status     string `json:"status"`
		ReviewNote string `json:"reviewNote"`
	}
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	if !contains(jobStates, in.Status) {
		badRequest(c, "unknown status")
		return
	}
	in.ReviewNote = truncate(strings.TrimSpace(in.ReviewNote), 2000)
	if in.Status == "rejected" && in.ReviewNote == "" {
		badRequest(c, "tell the employer why the posting was not approved")
		return
	}
	u, _ := md.CurrentUser(c)
	j, err := s.store.SetJobStatus(c.Request.Context(), db.SetJobStatusParams{
		ID: id, Status: in.Status, ReviewNote: in.ReviewNote,
		ReviewedBy: currentUserID(c),
	})
	if err != nil {
		dbError(c, err)
		return
	}
	s.audit(c, "review", "job", strconv.FormatInt(id, 10), gin.H{"status": j.Status, "by": u.Email})
	c.JSON(http.StatusOK, toJobDTO(j))
}
