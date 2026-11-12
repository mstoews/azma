package api

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgtype"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	"golang.org/x/sync/errgroup"
)

// ---- public site -------------------------------------------------------

type settingsDTO struct {
	SiteName        string    `json:"siteName"`
	Tagline         string    `json:"tagline"`
	HomeDescription string    `json:"homeDescription"`
	HomeHeaderImage string    `json:"homeHeaderImage"`
	Logo            string    `json:"logo"`
	UpdatedAt       time.Time `json:"updatedAt"`
}

func toSettingsDTO(s db.SiteSetting) settingsDTO {
	return settingsDTO{s.SiteName, s.Tagline, s.HomeDescription, s.HomeHeaderImage, s.Logo, s.UpdatedAt}
}

type publicPage struct {
	ID       int64  `json:"id"`
	Slug     string `json:"slug"`
	Title    string `json:"title"`
	Hero     string `json:"hero"`
	Content  string `json:"content"`
	LegacyID *int32 `json:"legacyId"`
}

type publicProfile struct {
	ID       int64    `json:"id"`
	Slug     string   `json:"slug"`
	Title    string   `json:"title"`
	Excerpt  []string `json:"excerpt"`
	Thumb    string   `json:"thumb"`
	Hero     string   `json:"hero"`
	Content  string   `json:"content"`
	LegacyID *int32   `json:"legacyId"`
}

type publicNav struct {
	Label  string `json:"label"`
	Link   string `json:"link,omitempty"`
	Href   string `json:"href,omitempty"`
	PageID *int64 `json:"pageId,omitempty"`
}

type publicSite struct {
	Settings settingsDTO     `json:"settings"`
	Pages    []publicPage    `json:"pages"`
	Profiles []publicProfile `json:"profiles"`
	Nav      []publicNav     `json:"nav"`
}

// getPublicSite returns everything the public site renders, in one response.
// The site is small (a handful of pages and profiles) so one request beats a
// request per route. Drafts are excluded.
func (s *Server) getPublicSite(c *gin.Context) {
	ctx := c.Request.Context()
	var (
		settings db.SiteSetting
		pages    []db.Page
		profiles []db.Profile
		nav      []db.ListNavItemsRow
	)
	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() (err error) { settings, err = s.store.GetSettings(gctx); return })
	g.Go(func() (err error) { pages, err = s.store.ListPublishedPages(gctx); return })
	g.Go(func() (err error) { profiles, err = s.store.ListPublishedProfiles(gctx); return })
	g.Go(func() (err error) { nav, err = s.store.ListNavItems(gctx); return })
	if err := g.Wait(); err != nil {
		dbError(c, err)
		return
	}

	out := publicSite{
		Settings: toSettingsDTO(settings),
		Pages:    make([]publicPage, 0, len(pages)),
		Profiles: make([]publicProfile, 0, len(profiles)),
		Nav:      make([]publicNav, 0, len(nav)),
	}
	for _, p := range pages {
		out.Pages = append(out.Pages, publicPage{p.ID, p.Slug, p.Title, p.Hero, p.Content, int4Ptr(p.LegacyWpID)})
	}
	for _, p := range profiles {
		ex := p.Excerpt
		if ex == nil {
			ex = []string{}
		}
		out.Profiles = append(out.Profiles, publicProfile{p.ID, p.Slug, p.Title, ex, p.Thumb, p.Hero, p.Content, int4Ptr(p.LegacyWpID)})
	}
	for _, n := range nav {
		switch {
		case n.Href.Valid:
			out.Nav = append(out.Nav, publicNav{Label: n.Label, Href: n.Href.String})
		case n.PageSlug.Valid && n.PagePublished.Valid && n.PagePublished.Bool:
			// Links to draft pages are hidden rather than left dangling.
			id := n.PageID.Int64
			out.Nav = append(out.Nav, publicNav{Label: n.Label, Link: "/" + n.PageSlug.String, PageID: &id})
		}
	}
	// Short cache: edits show up within a minute without a deploy.
	c.Header("Cache-Control", "public, max-age=60")
	c.JSON(http.StatusOK, out)
}

// ---- navigation --------------------------------------------------------

type navDTO struct {
	ID            int64  `json:"id"`
	Label         string `json:"label"`
	PageID        *int64 `json:"pageId"`
	Href          string `json:"href"`
	SortOrder     int32  `json:"sortOrder"`
	PageSlug      string `json:"pageSlug,omitempty"`
	PagePublished bool   `json:"pagePublished"`
}

func (s *Server) listNav(c *gin.Context) {
	rows, err := s.store.ListNavItems(c.Request.Context())
	if err != nil {
		dbError(c, err)
		return
	}
	out := make([]navDTO, len(rows))
	for i, n := range rows {
		d := navDTO{ID: n.ID, Label: n.Label, Href: n.Href.String, SortOrder: n.SortOrder,
			PageSlug: n.PageSlug.String, PagePublished: n.PagePublished.Bool}
		if n.PageID.Valid {
			id := n.PageID.Int64
			d.PageID = &id
		}
		out[i] = d
	}
	c.JSON(http.StatusOK, out)
}

type navInput struct {
	Label  string `json:"label"`
	PageID *int64 `json:"pageId"`
	Href   string `json:"href"`
}

// replaceNav swaps the whole menu in one transaction. The menu is a short
// ordered list edited as a unit, so replace-all is simpler and safer than
// per-item PATCHes that can interleave.
func (s *Server) replaceNav(c *gin.Context) {
	var in struct {
		Items []navInput `json:"items"`
	}
	if err := c.ShouldBindJSON(&in); err != nil || len(in.Items) > 50 {
		badRequest(c, "expected {\"items\": [...]} with at most 50 items")
		return
	}
	for i := range in.Items {
		it := &in.Items[i]
		it.Label = strings.TrimSpace(it.Label)
		it.Href = strings.TrimSpace(it.Href)
		if it.Label == "" {
			badRequest(c, "every menu item needs a label")
			return
		}
		if (it.PageID == nil) == (it.Href == "") {
			badRequest(c, "menu item '"+it.Label+"' must link to exactly one of a page or a URL")
			return
		}
		if it.Href != "" && !validLinkURL(it.Href) {
			badRequest(c, "menu item '"+it.Label+"' has an invalid URL")
			return
		}
	}
	ctx := c.Request.Context()
	before, _ := s.store.ListNavItems(ctx)
	err := s.store.ExecTx(ctx, func(q db.Querier) error {
		if err := q.DeleteAllNavItems(ctx); err != nil {
			return err
		}
		for i, it := range in.Items {
			p := db.CreateNavItemParams{Label: it.Label, SortOrder: int32((i + 1) * 10)}
			if it.PageID != nil {
				p.PageID = pgtype.Int8{Int64: *it.PageID, Valid: true}
			} else {
				p.Href = pgtype.Text{String: it.Href, Valid: true}
			}
			if _, err := q.CreateNavItem(ctx, p); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		dbError(c, err)
		return
	}
	s.audit(c, "update", "nav", "", gin.H{"before": before, "after": in.Items})
	s.listNav(c)
}

// ---- settings ----------------------------------------------------------

func (s *Server) getSettings(c *gin.Context) {
	st, err := s.store.GetSettings(c.Request.Context())
	if err != nil {
		dbError(c, err)
		return
	}
	c.JSON(http.StatusOK, toSettingsDTO(st))
}

func (s *Server) updateSettings(c *gin.Context) {
	var in settingsDTO
	if err := c.ShouldBindJSON(&in); err != nil {
		badRequest(c, "invalid request body")
		return
	}
	in.SiteName = strings.TrimSpace(in.SiteName)
	if in.SiteName == "" {
		badRequest(c, "site name is required")
		return
	}
	if !validAssetURL(in.Logo) || !validAssetURL(in.HomeHeaderImage) {
		badRequest(c, "images must be site paths (/...) or http(s) URLs")
		return
	}
	ctx := c.Request.Context()
	before, _ := s.store.GetSettings(ctx)
	st, err := s.store.UpdateSettings(ctx, db.UpdateSettingsParams{
		SiteName: in.SiteName, Tagline: strings.TrimSpace(in.Tagline),
		HomeDescription: strings.TrimSpace(in.HomeDescription),
		HomeHeaderImage: strings.TrimSpace(in.HomeHeaderImage), Logo: strings.TrimSpace(in.Logo),
		UpdatedBy: currentUserID(c),
	})
	if err != nil {
		dbError(c, err)
		return
	}
	s.audit(c, "update", "settings", "", gin.H{"before": toSettingsDTO(before), "after": toSettingsDTO(st)})
	c.JSON(http.StatusOK, toSettingsDTO(st))
}
