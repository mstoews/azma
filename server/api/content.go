package api

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
)

const maxContentBytes = 1 << 20

// ---- DTOs --------------------------------------------------------------

type pageDTO struct {
	ID         int64     `json:"id"`
	Slug       string    `json:"slug"`
	Title      string    `json:"title"`
	Hero       string    `json:"hero"`
	Content    string    `json:"content"`
	Published  bool      `json:"published"`
	SortOrder  int32     `json:"sortOrder"`
	LegacyWpID *int32    `json:"legacyWpId"`
	CreatedAt  time.Time `json:"createdAt"`
	UpdatedAt  time.Time `json:"updatedAt"`
	// Keyed by locale; only locales with a translation appear.
	Translations map[string]pageTranslationDTO `json:"translations"`
}

func toPageDTO(p db.Page, tr []db.PageTranslation) pageDTO {
	return pageDTO{p.ID, p.Slug, p.Title, p.Hero, p.Content, p.Published, p.SortOrder,
		int4Ptr(p.LegacyWpID), p.CreatedAt, p.UpdatedAt, pageTranslationMap(tr)}
}

type profileDTO struct {
	ID         int64     `json:"id"`
	Slug       string    `json:"slug"`
	Title      string    `json:"title"`
	Excerpt    []string  `json:"excerpt"`
	Thumb      string    `json:"thumb"`
	Hero       string    `json:"hero"`
	Content    string    `json:"content"`
	Published  bool      `json:"published"`
	SortOrder  int32     `json:"sortOrder"`
	LegacyWpID *int32    `json:"legacyWpId"`
	CreatedAt  time.Time `json:"createdAt"`
	UpdatedAt  time.Time `json:"updatedAt"`
	// Keyed by locale; only locales with a translation appear.
	Translations map[string]profileTranslationDTO `json:"translations"`
}

func toProfileDTO(p db.Profile, tr []db.ProfileTranslation) profileDTO {
	ex := p.Excerpt
	if ex == nil {
		ex = []string{}
	}
	return profileDTO{p.ID, p.Slug, p.Title, ex, p.Thumb, p.Hero, p.Content, p.Published, p.SortOrder,
		int4Ptr(p.LegacyWpID), p.CreatedAt, p.UpdatedAt, profileTranslationMap(tr)}
}

// ---- inputs ------------------------------------------------------------

type pageInput struct {
	Slug      string `json:"slug"`
	Title     string `json:"title"`
	Hero      string `json:"hero"`
	Content   string `json:"content"`
	Published bool   `json:"published"`
	SortOrder int32  `json:"sortOrder"`
	// Optional; see savePageTranslations for what it changes.
	Translations map[string]pageTranslationDTO `json:"translations"`
}

func (in *pageInput) normalize() string {
	if msg := in.normalizeTranslations(); msg != "" {
		return msg
	}
	return in.normalizeBase()
}

func (in *pageInput) normalizeTranslations() string {
	if msg := checkLocales(in.Translations); msg != "" {
		return msg
	}
	for l, t := range in.Translations {
		if msg := t.normalize(); msg != "" {
			return msg
		}
		in.Translations[l] = t
	}
	return ""
}

func (in *pageInput) normalizeBase() string {
	in.Title = strings.TrimSpace(in.Title)
	in.Hero = strings.TrimSpace(in.Hero)
	in.Slug = strings.TrimSpace(in.Slug)
	if in.Slug == "" {
		in.Slug = Slugify(in.Title)
	}
	switch {
	case in.Title == "":
		return "title is required"
	case len(in.Title) > 200:
		return "title is too long"
	case len(in.Content) > maxContentBytes:
		return "content is too large"
	case !validAssetURL(in.Hero):
		return "hero must be a site path (/...) or an http(s) URL"
	}
	in.Content = SanitizeContent(in.Content)
	return validSlug(in.Slug, true)
}

type profileInput struct {
	pageInput
	Excerpt []string `json:"excerpt"`
	Thumb   string   `json:"thumb"`
	// Shadows pageInput.Translations: profiles also translate the card text.
	Translations map[string]profileTranslationDTO `json:"translations"`
}

func (in *profileInput) normalize() string {
	if msg := checkLocales(in.Translations); msg != "" {
		return msg
	}
	for l, t := range in.Translations {
		if msg := t.normalize(); msg != "" {
			return msg
		}
		in.Translations[l] = t
	}
	if msg := in.pageInput.normalizeBase(); msg != "" && !strings.Contains(msg, "reserved") {
		return msg
	}
	in.Thumb = strings.TrimSpace(in.Thumb)
	if !validAssetURL(in.Thumb) {
		return "thumb must be a site path (/...) or an http(s) URL"
	}
	if len(in.Excerpt) > 10 {
		return "excerpt has too many lines"
	}
	lines := make([]string, 0, len(in.Excerpt))
	for _, l := range in.Excerpt {
		if l = strings.TrimSpace(l); l != "" {
			lines = append(lines, l)
		}
	}
	in.Excerpt = lines
	// Profiles live under /profile/<slug>, so top-level reservations do not apply.
	return validSlug(in.Slug, false)
}

type orderInput struct {
	IDs []int64 `json:"ids" binding:"required"`
}

// ---- pages -------------------------------------------------------------

func (s *Server) listPages(c *gin.Context) {
	ctx := c.Request.Context()
	rows, err := s.store.ListPages(ctx)
	if err != nil {
		dbError(c, err)
		return
	}
	tr, err := s.store.ListPageTranslations(ctx)
	if err != nil {
		dbError(c, err)
		return
	}
	byPage := groupPageTranslations(tr)
	out := make([]pageDTO, len(rows))
	for i, p := range rows {
		out[i] = toPageDTO(p, byPage[p.ID])
	}
	c.JSON(http.StatusOK, out)
}

// loadPage reads a page with its translations.
func loadPage(ctx context.Context, q db.Querier, id int64) (pageDTO, error) {
	p, err := q.GetPage(ctx, id)
	if err != nil {
		return pageDTO{}, err
	}
	tr, err := q.ListPageTranslationsForPage(ctx, id)
	if err != nil {
		return pageDTO{}, err
	}
	return toPageDTO(p, tr), nil
}

func (s *Server) getPage(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	p, err := loadPage(c.Request.Context(), s.store, id)
	if err != nil {
		dbError(c, err)
		return
	}
	c.JSON(http.StatusOK, p)
}

func (s *Server) createPage(c *gin.Context) {
	var in pageInput
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	if msg := in.normalize(); msg != "" {
		badRequest(c, msg)
		return
	}
	ctx := c.Request.Context()
	by := currentUserID(c)
	var out pageDTO
	err := s.store.ExecTx(ctx, func(q db.Querier) error {
		p, err := q.CreatePage(ctx, db.CreatePageParams{
			Slug: in.Slug, Title: in.Title, Hero: in.Hero, Content: in.Content,
			Published: in.Published, SortOrder: in.SortOrder, UpdatedBy: by,
		})
		if err != nil {
			return err
		}
		if err := savePageTranslations(ctx, q, p.ID, by, in.Translations); err != nil {
			return err
		}
		out, err = loadPage(ctx, q, p.ID)
		return err
	})
	if err != nil {
		dbError(c, err)
		return
	}
	s.audit(c, "create", "page", strconv.FormatInt(out.ID, 10), gin.H{"after": out})
	c.JSON(http.StatusCreated, out)
}

func (s *Server) updatePage(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	var in pageInput
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	if msg := in.normalize(); msg != "" {
		badRequest(c, msg)
		return
	}
	ctx := c.Request.Context()
	by := currentUserID(c)
	var before, after pageDTO
	err := s.store.ExecTx(ctx, func(q db.Querier) error {
		var err error
		if before, err = loadPage(ctx, q, id); err != nil {
			return err
		}
		if _, err = q.UpdatePage(ctx, db.UpdatePageParams{
			ID: id, Slug: in.Slug, Title: in.Title, Hero: in.Hero, Content: in.Content,
			Published: in.Published, SortOrder: in.SortOrder, UpdatedBy: by,
		}); err != nil {
			return err
		}
		if err = savePageTranslations(ctx, q, id, by, in.Translations); err != nil {
			return err
		}
		after, err = loadPage(ctx, q, id)
		return err
	})
	if err != nil {
		dbError(c, err)
		return
	}
	s.audit(c, "update", "page", strconv.FormatInt(id, 10), gin.H{"before": before, "after": after})
	c.JSON(http.StatusOK, after)
}

func (s *Server) deletePage(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	ctx := c.Request.Context()
	before, err := loadPage(ctx, s.store, id)
	if err != nil {
		dbError(c, err)
		return
	}
	if err := s.store.DeletePage(ctx, id); err != nil {
		dbError(c, err)
		return
	}
	s.audit(c, "delete", "page", strconv.FormatInt(id, 10), gin.H{"before": before})
	c.Status(http.StatusNoContent)
}

func (s *Server) reorderPages(c *gin.Context) {
	s.reorder(c, "page", func(q db.Querier, id int64, order int32) error {
		return q.SetPageSortOrder(c.Request.Context(), db.SetPageSortOrderParams{ID: id, SortOrder: order})
	})
}

// ---- profiles ----------------------------------------------------------

func (s *Server) listProfiles(c *gin.Context) {
	ctx := c.Request.Context()
	rows, err := s.store.ListProfiles(ctx)
	if err != nil {
		dbError(c, err)
		return
	}
	tr, err := s.store.ListProfileTranslations(ctx)
	if err != nil {
		dbError(c, err)
		return
	}
	byProfile := groupProfileTranslations(tr)
	out := make([]profileDTO, len(rows))
	for i, p := range rows {
		out[i] = toProfileDTO(p, byProfile[p.ID])
	}
	c.JSON(http.StatusOK, out)
}

// loadProfile reads a profile with its translations.
func loadProfile(ctx context.Context, q db.Querier, id int64) (profileDTO, error) {
	p, err := q.GetProfile(ctx, id)
	if err != nil {
		return profileDTO{}, err
	}
	tr, err := q.ListProfileTranslationsForProfile(ctx, id)
	if err != nil {
		return profileDTO{}, err
	}
	return toProfileDTO(p, tr), nil
}

func (s *Server) getProfile(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	p, err := loadProfile(c.Request.Context(), s.store, id)
	if err != nil {
		dbError(c, err)
		return
	}
	c.JSON(http.StatusOK, p)
}

func (s *Server) createProfile(c *gin.Context) {
	var in profileInput
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	if msg := in.normalize(); msg != "" {
		badRequest(c, msg)
		return
	}
	ctx := c.Request.Context()
	by := currentUserID(c)
	var out profileDTO
	err := s.store.ExecTx(ctx, func(q db.Querier) error {
		p, err := q.CreateProfile(ctx, db.CreateProfileParams{
			Slug: in.Slug, Title: in.Title, Excerpt: in.Excerpt, Thumb: in.Thumb, Hero: in.Hero,
			Content: in.Content, Published: in.Published, SortOrder: in.SortOrder, UpdatedBy: by,
		})
		if err != nil {
			return err
		}
		if err := saveProfileTranslations(ctx, q, p.ID, by, in.Translations); err != nil {
			return err
		}
		out, err = loadProfile(ctx, q, p.ID)
		return err
	})
	if err != nil {
		dbError(c, err)
		return
	}
	s.audit(c, "create", "profile", strconv.FormatInt(out.ID, 10), gin.H{"after": out})
	c.JSON(http.StatusCreated, out)
}

func (s *Server) updateProfile(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	var in profileInput
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	if msg := in.normalize(); msg != "" {
		badRequest(c, msg)
		return
	}
	ctx := c.Request.Context()
	by := currentUserID(c)
	var before, after profileDTO
	err := s.store.ExecTx(ctx, func(q db.Querier) error {
		var err error
		if before, err = loadProfile(ctx, q, id); err != nil {
			return err
		}
		if _, err = q.UpdateProfile(ctx, db.UpdateProfileParams{
			ID: id, Slug: in.Slug, Title: in.Title, Excerpt: in.Excerpt, Thumb: in.Thumb, Hero: in.Hero,
			Content: in.Content, Published: in.Published, SortOrder: in.SortOrder, UpdatedBy: by,
		}); err != nil {
			return err
		}
		if err = saveProfileTranslations(ctx, q, id, by, in.Translations); err != nil {
			return err
		}
		after, err = loadProfile(ctx, q, id)
		return err
	})
	if err != nil {
		dbError(c, err)
		return
	}
	s.audit(c, "update", "profile", strconv.FormatInt(id, 10), gin.H{"before": before, "after": after})
	c.JSON(http.StatusOK, after)
}

func (s *Server) deleteProfile(c *gin.Context) {
	id, ok := parseInt64Param(c, "id")
	if !ok {
		return
	}
	ctx := c.Request.Context()
	before, err := loadProfile(ctx, s.store, id)
	if err != nil {
		dbError(c, err)
		return
	}
	if err := s.store.DeleteProfile(ctx, id); err != nil {
		dbError(c, err)
		return
	}
	s.audit(c, "delete", "profile", strconv.FormatInt(id, 10), gin.H{"before": before})
	c.Status(http.StatusNoContent)
}

func (s *Server) reorderProfiles(c *gin.Context) {
	s.reorder(c, "profile", func(q db.Querier, id int64, order int32) error {
		return q.SetProfileSortOrder(c.Request.Context(), db.SetProfileSortOrderParams{ID: id, SortOrder: order})
	})
}

// reorder assigns sort_order 10, 20, 30... in the order the IDs were given.
func (s *Server) reorder(c *gin.Context, entity string, set func(db.Querier, int64, int32) error) {
	var in orderInput
	if err := c.ShouldBindJSON(&in); err != nil || len(in.IDs) > 1000 {
		badRequest(c, "expected {\"ids\": [...]}")
		return
	}
	err := s.store.ExecTx(c.Request.Context(), func(q db.Querier) error {
		for i, id := range in.IDs {
			if err := set(q, id, int32((i+1)*10)); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		dbError(c, err)
		return
	}
	s.audit(c, "reorder", entity, "", gin.H{"ids": in.IDs})
	c.Status(http.StatusNoContent)
}
