// Accounts for the mobile app: sign-up, and the candidate and employer
// profiles behind it. The CMS side of the server (pages, media, users) is
// unchanged; these routes are what the iOS app signs in to.
package api

import (
	"errors"
	"net/http"
	"net/mail"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	md "github.com/mstoews/azma-associates/server/middleware"
	"github.com/rs/zerolog/log"
)

// ---- shared vocabulary -------------------------------------------------
//
// One list per field the app offers as a picker, so a value the server will
// reject is never selectable. sectors mirrors the "Our Expertise" page.

var sectors = []string{
	"Asset Management",
	"Alternative Investment Management",
	"Private Equity",
	"Hedge Fund",
	"Real Estate",
	"Fund Portfolio Companies",
	"Trust Bank",
	"Securities",
	"Investment Banking",
	"Bank",
	"M&A",
	"Information Technology",
	"Consulting Firms",
	"Healthcare",
	"Industrial",
	"Startup",
}

var (
	employmentTypes    = []string{"full_time", "contract", "part_time", "internship"}
	currencies         = []string{"JPY", "SGD", "USD", "EUR", "GBP", "HKD", "AUD"}
	offices            = []string{"tokyo", "singapore"}
	inquiryKinds       = []string{"hiring", "career", "general"}
	appRoles           = []string{"candidate", "employer"}
	applicationStates  = []string{"submitted", "under_review", "shortlisted", "interviewing", "offer", "placed", "rejected", "withdrawn"}
	jobStates          = []string{"draft", "pending", "published", "filled", "closed", "rejected"}
	maxResumesPerUser  = 5
	maxFreeTextBytes   = 8000
	maxShortTextBytes  = 200
	maxListEntries     = 12
	maxListEntryLength = 60
)

func contains(list []string, v string) bool {
	for _, s := range list {
		if s == v {
			return true
		}
	}
	return false
}

// getOptions lets the app fill its pickers from the server rather than from a
// copy of these lists that could drift out of step with the CHECK constraints.
func (s *Server) getOptions(c *gin.Context) {
	c.Header("Cache-Control", "public, max-age=3600")
	c.JSON(http.StatusOK, gin.H{
		"sectors":            sectors,
		"employmentTypes":    employmentTypes,
		"currencies":         currencies,
		"offices":            offices,
		"inquiryKinds":       inquiryKinds,
		"jobStatuses":        jobStates,
		"applicationStates":  applicationStates,
		"minPasswordLength":  MinPasswordLength,
		"maxResumesPerUser":  maxResumesPerUser,
		"resumeMaxBytes":     s.config.MediaMaxBytes,
		"resumeContentTypes": []string{"application/pdf", "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"},
	})
}

// ---- input helpers -----------------------------------------------------

// cleanLine trims a single-line field and caps its length.
func cleanLine(v string) string { return truncate(strings.TrimSpace(v), maxShortTextBytes) }

// cleanList trims a repeated field, drops blanks and duplicates, and caps both
// the number of entries and their length.
func cleanList(in []string) []string {
	out := make([]string, 0, len(in))
	seen := map[string]bool{}
	for _, v := range in {
		v = truncate(strings.TrimSpace(v), maxListEntryLength)
		if v == "" || seen[v] {
			continue
		}
		seen[v] = true
		out = append(out, v)
		if len(out) == maxListEntries {
			break
		}
	}
	return out
}

func validEmail(v string) bool {
	addr, err := mail.ParseAddress(v)
	return err == nil && addr.Address == v && len(v) <= 254
}

// ---- sign-up -----------------------------------------------------------

type registerInput struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	Role     string `json:"role"`
	Name     string `json:"name"`
	// Employers only; saved straight onto the new employer profile so the
	// first job posting already knows the company.
	Company string `json:"company"`
}

// register creates a candidate or employer account and signs it in. The role
// comes from the client but is restricted to the two app roles: an
// administrator can only be created with cmd/admin or by another admin.
func (s *Server) register(c *gin.Context) {
	var in registerInput
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	in.Email = strings.TrimSpace(in.Email)
	in.Name = cleanLine(in.Name)
	in.Company = cleanLine(in.Company)
	if !validEmail(in.Email) {
		badRequest(c, "a valid email address is required")
		return
	}
	if !contains(appRoles, in.Role) {
		badRequest(c, "role must be 'candidate' or 'employer'")
		return
	}
	if in.Name == "" {
		badRequest(c, "name is required")
		return
	}
	hash, err := HashPassword(in.Password)
	if err != nil {
		badRequest(c, err.Error())
		return
	}

	ctx := c.Request.Context()
	var user db.User
	// The account and its (empty) profile row are created together, so every
	// signed-in user has a profile to read back.
	err = s.store.ExecTx(ctx, func(q db.Querier) error {
		u, err := q.CreateUser(ctx, db.CreateUserParams{
			Email: in.Email, Name: in.Name, PasswordHash: hash, Role: in.Role,
		})
		if err != nil {
			return err
		}
		user = u
		if in.Role == "candidate" {
			_, err = q.UpsertCandidateProfile(ctx, db.UpsertCandidateProfileParams{
				UserID: u.ID, FullName: in.Name, Sectors: []string{}, DesiredRoles: []string{},
				Languages: []string{}, OpenToOffers: true,
			})
			return err
		}
		_, err = q.UpsertEmployerProfile(ctx, db.UpsertEmployerProfileParams{
			UserID: u.ID, Company: in.Company, ContactName: in.Name,
		})
		return err
	})
	if err != nil {
		dbError(c, err)
		return
	}

	token, expires, ok := s.issueSession(c, user)
	if !ok {
		return
	}
	md.SetUser(c, user)
	s.audit(c, "register", "user", user.ID.String(), gin.H{"role": user.Role})
	c.JSON(http.StatusCreated, gin.H{"token": token, "expiresAt": expires, "user": toUserDTO(user)})
}

// ---- candidate profile -------------------------------------------------

type candidateProfileDTO struct {
	FullName          string     `json:"fullName"`
	Headline          string     `json:"headline"`
	Summary           string     `json:"summary"`
	Location          string     `json:"location"`
	Phone             string     `json:"phone"`
	LinkedinURL       string     `json:"linkedinUrl"`
	CurrentEmployer   string     `json:"currentEmployer"`
	CurrentTitle      string     `json:"currentTitle"`
	YearsExperience   int32      `json:"yearsExperience"`
	Sectors           []string   `json:"sectors"`
	DesiredRoles      []string   `json:"desiredRoles"`
	Languages         []string   `json:"languages"`
	WorkAuthorization string     `json:"workAuthorization"`
	SalaryExpectation string     `json:"salaryExpectation"`
	OpenToOffers      bool       `json:"openToOffers"`
	Submitted         bool       `json:"submitted"`
	SubmittedAt       *time.Time `json:"submittedAt"`
	UpdatedAt         time.Time  `json:"updatedAt"`
}

func toCandidateProfileDTO(p db.CandidateProfile) candidateProfileDTO {
	return candidateProfileDTO{
		FullName: p.FullName, Headline: p.Headline, Summary: p.Summary, Location: p.Location,
		Phone: p.Phone, LinkedinURL: p.LinkedinUrl, CurrentEmployer: p.CurrentEmployer,
		CurrentTitle: p.CurrentTitle, YearsExperience: p.YearsExperience,
		Sectors: orEmpty(p.Sectors), DesiredRoles: orEmpty(p.DesiredRoles), Languages: orEmpty(p.Languages),
		WorkAuthorization: p.WorkAuthorization, SalaryExpectation: p.SalaryExpectation,
		OpenToOffers: p.OpenToOffers, Submitted: p.Submitted, SubmittedAt: p.SubmittedAt,
		UpdatedAt: p.UpdatedAt,
	}
}

func orEmpty(v []string) []string {
	if v == nil {
		return []string{}
	}
	return v
}

type candidateProfileInput struct {
	FullName          string   `json:"fullName"`
	Headline          string   `json:"headline"`
	Summary           string   `json:"summary"`
	Location          string   `json:"location"`
	Phone             string   `json:"phone"`
	LinkedinURL       string   `json:"linkedinUrl"`
	CurrentEmployer   string   `json:"currentEmployer"`
	CurrentTitle      string   `json:"currentTitle"`
	YearsExperience   int32    `json:"yearsExperience"`
	Sectors           []string `json:"sectors"`
	DesiredRoles      []string `json:"desiredRoles"`
	Languages         []string `json:"languages"`
	WorkAuthorization string   `json:"workAuthorization"`
	SalaryExpectation string   `json:"salaryExpectation"`
	OpenToOffers      bool     `json:"openToOffers"`
}

func (in *candidateProfileInput) normalize() string {
	in.FullName = cleanLine(in.FullName)
	in.Headline = cleanLine(in.Headline)
	in.Location = cleanLine(in.Location)
	in.Phone = cleanLine(in.Phone)
	in.LinkedinURL = cleanLine(in.LinkedinURL)
	in.CurrentEmployer = cleanLine(in.CurrentEmployer)
	in.CurrentTitle = cleanLine(in.CurrentTitle)
	in.WorkAuthorization = cleanLine(in.WorkAuthorization)
	in.SalaryExpectation = cleanLine(in.SalaryExpectation)
	in.Summary = strings.TrimSpace(in.Summary)
	in.Sectors = cleanList(in.Sectors)
	in.DesiredRoles = cleanList(in.DesiredRoles)
	in.Languages = cleanList(in.Languages)
	switch {
	case in.FullName == "":
		return "your name is required"
	case len(in.Summary) > maxFreeTextBytes:
		return "summary is too long"
	case in.YearsExperience < 0 || in.YearsExperience > 70:
		return "years of experience must be between 0 and 70"
	case in.LinkedinURL != "" && !validAssetURL(in.LinkedinURL):
		return "LinkedIn must be an http(s) URL"
	}
	for _, sec := range in.Sectors {
		if !contains(sectors, sec) {
			return "unknown sector: " + sec
		}
	}
	return ""
}

// candidateOverview is everything the app's candidate tabs need in one trip.
type candidateOverview struct {
	Profile      candidateProfileDTO `json:"profile"`
	Resumes      []resumeDTO         `json:"resumes"`
	Applications []applicationDTO    `json:"applications"`
	SavedJobs    []jobDTO            `json:"savedJobs"`
}

func (s *Server) getCandidateMe(c *gin.Context) {
	u, _ := md.CurrentUser(c)
	ctx := c.Request.Context()

	profile, err := s.store.GetCandidateProfile(ctx, u.ID)
	if err != nil {
		if !errors.Is(err, pgx.ErrNoRows) {
			dbError(c, err)
			return
		}
		// An account created before this table existed, or one whose profile
		// was removed: hand back a blank one rather than a 404.
		profile = db.CandidateProfile{UserID: u.ID, FullName: u.Name, OpenToOffers: true}
	}
	resumes, err := s.store.ListResumes(ctx, u.ID)
	if err != nil {
		dbError(c, err)
		return
	}
	apps, err := s.store.ListApplicationsForCandidate(ctx, u.ID)
	if err != nil {
		dbError(c, err)
		return
	}
	saved, err := s.store.ListSavedJobs(ctx, u.ID)
	if err != nil {
		dbError(c, err)
		return
	}

	out := candidateOverview{
		Profile:      toCandidateProfileDTO(profile),
		Resumes:      make([]resumeDTO, len(resumes)),
		Applications: make([]applicationDTO, len(apps)),
		SavedJobs:    make([]jobDTO, len(saved)),
	}
	for i, r := range resumes {
		out.Resumes[i] = toResumeDTO(r)
	}
	for i, a := range apps {
		out.Applications[i] = toCandidateApplicationDTO(a)
	}
	for i, row := range saved {
		out.SavedJobs[i] = toPublicJobDTO(row.Job)
	}
	c.JSON(http.StatusOK, out)
}

func (s *Server) putCandidateProfile(c *gin.Context) {
	var in candidateProfileInput
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	if msg := in.normalize(); msg != "" {
		badRequest(c, msg)
		return
	}
	u, _ := md.CurrentUser(c)
	p, err := s.store.UpsertCandidateProfile(c.Request.Context(), db.UpsertCandidateProfileParams{
		UserID: u.ID, FullName: in.FullName, Headline: in.Headline, Summary: in.Summary,
		Location: in.Location, Phone: in.Phone, LinkedinUrl: in.LinkedinURL,
		CurrentEmployer: in.CurrentEmployer, CurrentTitle: in.CurrentTitle,
		YearsExperience: in.YearsExperience, Sectors: in.Sectors, DesiredRoles: in.DesiredRoles,
		Languages: in.Languages, WorkAuthorization: in.WorkAuthorization,
		SalaryExpectation: in.SalaryExpectation, OpenToOffers: in.OpenToOffers,
	})
	if err != nil {
		dbError(c, err)
		return
	}
	c.JSON(http.StatusOK, toCandidateProfileDTO(p))
}

// submitCandidateProfile is the candidate asking us to represent them, which
// is what puts their profile in front of a consultant. Withdrawing is the same
// call with submitted: false.
func (s *Server) submitCandidateProfile(c *gin.Context) {
	var in struct {
		Submitted bool `json:"submitted"`
	}
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	u, _ := md.CurrentUser(c)
	ctx := c.Request.Context()
	if in.Submitted {
		// Nothing useful reaches a consultant without a resume on file.
		n, err := s.store.CountResumes(ctx, u.ID)
		if err != nil {
			dbError(c, err)
			return
		}
		if n == 0 {
			badRequest(c, "add your resume before submitting your profile")
			return
		}
	}
	p, err := s.store.SubmitCandidateProfile(ctx, db.SubmitCandidateProfileParams{
		UserID: u.ID, Submitted: in.Submitted,
	})
	if err != nil {
		dbError(c, err)
		return
	}
	if in.Submitted {
		log.Info().Str("candidate", u.Email).Msg("candidate profile submitted")
	}
	c.JSON(http.StatusOK, toCandidateProfileDTO(p))
}

// ---- employer profile --------------------------------------------------

type employerProfileDTO struct {
	Company     string    `json:"company"`
	ContactName string    `json:"contactName"`
	ContactRole string    `json:"contactRole"`
	Phone       string    `json:"phone"`
	Website     string    `json:"website"`
	Location    string    `json:"location"`
	About       string    `json:"about"`
	UpdatedAt   time.Time `json:"updatedAt"`
}

func toEmployerProfileDTO(p db.EmployerProfile) employerProfileDTO {
	return employerProfileDTO{p.Company, p.ContactName, p.ContactRole, p.Phone, p.Website,
		p.Location, p.About, p.UpdatedAt}
}

type employerProfileInput struct {
	Company     string `json:"company"`
	ContactName string `json:"contactName"`
	ContactRole string `json:"contactRole"`
	Phone       string `json:"phone"`
	Website     string `json:"website"`
	Location    string `json:"location"`
	About       string `json:"about"`
}

func (in *employerProfileInput) normalize() string {
	in.Company = cleanLine(in.Company)
	in.ContactName = cleanLine(in.ContactName)
	in.ContactRole = cleanLine(in.ContactRole)
	in.Phone = cleanLine(in.Phone)
	in.Website = cleanLine(in.Website)
	in.Location = cleanLine(in.Location)
	in.About = strings.TrimSpace(in.About)
	switch {
	case in.Company == "":
		return "company is required"
	case in.ContactName == "":
		return "contact name is required"
	case len(in.About) > maxFreeTextBytes:
		return "about is too long"
	case in.Website != "" && !validAssetURL(in.Website):
		return "website must be an http(s) URL"
	}
	return ""
}

type employerOverview struct {
	Profile employerProfileDTO `json:"profile"`
	Jobs    []jobDTO           `json:"jobs"`
}

func (s *Server) getEmployerMe(c *gin.Context) {
	u, _ := md.CurrentUser(c)
	ctx := c.Request.Context()
	profile, err := s.store.GetEmployerProfile(ctx, u.ID)
	if err != nil {
		if !errors.Is(err, pgx.ErrNoRows) {
			dbError(c, err)
			return
		}
		profile = db.EmployerProfile{UserID: u.ID, ContactName: u.Name}
	}
	rows, err := s.store.ListJobsForEmployer(ctx, u.ID)
	if err != nil {
		dbError(c, err)
		return
	}
	out := employerOverview{Profile: toEmployerProfileDTO(profile), Jobs: make([]jobDTO, len(rows))}
	for i, row := range rows {
		d := toJobDTO(row.Job)
		n := row.ApplicationCount
		d.ApplicationCount = &n
		out.Jobs[i] = d
	}
	c.JSON(http.StatusOK, out)
}

func (s *Server) putEmployerProfile(c *gin.Context) {
	var in employerProfileInput
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	if msg := in.normalize(); msg != "" {
		badRequest(c, msg)
		return
	}
	u, _ := md.CurrentUser(c)
	p, err := s.store.UpsertEmployerProfile(c.Request.Context(), db.UpsertEmployerProfileParams{
		UserID: u.ID, Company: in.Company, ContactName: in.ContactName, ContactRole: in.ContactRole,
		Phone: in.Phone, Website: in.Website, Location: in.Location, About: in.About,
	})
	if err != nil {
		dbError(c, err)
		return
	}
	c.JSON(http.StatusOK, toEmployerProfileDTO(p))
}
