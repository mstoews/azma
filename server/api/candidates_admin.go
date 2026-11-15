// The consultant's view of the candidate side: who has asked us to represent
// them, and the resume we hold for them.
package api

import (
	"net/http"

	"github.com/gin-gonic/gin"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
)

type candidateSummaryDTO struct {
	UserID           string              `json:"userId"`
	Email            string              `json:"email"`
	Profile          candidateProfileDTO `json:"profile"`
	ResumeCount      int64               `json:"resumeCount"`
	ApplicationCount int64               `json:"applicationCount"`
	LatestResumeID   *int64              `json:"latestResumeId"`
	LatestResumeName string              `json:"latestResumeFilename"`
}

func (s *Server) listCandidatesForAdmin(c *gin.Context) {
	limit, offset := pageParams(c, 50, 200)
	// Default to the people who have actually asked to be represented; the app
	// can ask for everyone with ?all=1.
	submittedOnly := c.Query("all") != "1"
	rows, err := s.store.ListCandidatesForAdmin(c.Request.Context(), db.ListCandidatesForAdminParams{
		SubmittedOnly: submittedOnly, Q: cleanLine(c.Query("q")), Lim: limit, Off: offset,
	})
	if err != nil {
		dbError(c, err)
		return
	}
	out := make([]candidateSummaryDTO, len(rows))
	for i, row := range rows {
		d := candidateSummaryDTO{
			UserID:           row.CandidateProfile.UserID.String(),
			Email:            row.Email,
			Profile:          toCandidateProfileDTO(row.CandidateProfile),
			ResumeCount:      row.ResumeCount,
			ApplicationCount: row.ApplicationCount,
			LatestResumeName: row.LatestResumeFilename,
		}
		if row.LatestResumeID > 0 {
			id := row.LatestResumeID
			d.LatestResumeID = &id
		}
		out[i] = d
	}
	c.JSON(http.StatusOK, gin.H{"candidates": out, "limit": limit, "offset": offset})
}

func (s *Server) getCandidateForAdmin(c *gin.Context) {
	id, ok := parseUUIDParam(c, "id")
	if !ok {
		return
	}
	ctx := c.Request.Context()
	row, err := s.store.GetCandidateForAdmin(ctx, id)
	if err != nil {
		dbError(c, err)
		return
	}
	resumes, err := s.store.ListResumes(ctx, id)
	if err != nil {
		dbError(c, err)
		return
	}
	apps, err := s.store.ListApplicationsForCandidate(ctx, id)
	if err != nil {
		dbError(c, err)
		return
	}
	outResumes := make([]resumeDTO, len(resumes))
	for i, r := range resumes {
		outResumes[i] = toResumeDTO(r)
	}
	outApps := make([]applicationDTO, len(apps))
	for i, a := range apps {
		outApps[i] = toCandidateApplicationDTO(a)
	}
	c.JSON(http.StatusOK, gin.H{
		"userId":       row.CandidateProfile.UserID.String(),
		"email":        row.Email,
		"profile":      toCandidateProfileDTO(row.CandidateProfile),
		"resumes":      outResumes,
		"applications": outApps,
	})
}
