package api

import (
	"context"
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
	// The language the text is in: "en", or a supported locale. Fields with
	// no translation are in English whatever this says.
	Locale   string          `json:"locale"`
	Settings settingsDTO     `json:"settings"`
	Pages    []publicPage    `json:"pages"`
	Profiles []publicProfile `json:"profiles"`
	Nav      []publicNav     `json:"nav"`
}

// getPublicSite returns everything the public site renders, in one response.
// The site is small (a handful of pages and profiles) so one request beats a
// request per route. Drafts are excluded.
//
// The language comes from ?lang= or Accept-Language (see requestLocale).
// Translated fields replace the English ones; anything untranslated stays in
// English, so callers never get an empty page.
func (s *Server) getPublicSite(c *gin.Context) {
	ctx := c.Request.Context()
	locale := requestLocale(c)
	var (
		settings  db.SiteSetting
		pages     []db.Page
		profiles  []db.Profile
		nav       []db.ListNavItemsRow
		pageTr    []db.PageTranslation
		profileTr []db.ProfileTranslation
		navTr     []db.NavItemTranslation
		setTr     []db.SiteSettingsTranslation
	)
	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() (err error) { settings, err = s.store.GetSettings(gctx); return })
	g.Go(func() (err error) { pages, err = s.store.ListPublishedPages(gctx); return })
	g.Go(func() (err error) { profiles, err = s.store.ListPublishedProfiles(gctx); return })
	g.Go(func() (err error) { nav, err = s.store.ListNavItems(gctx); return })
	if locale != defaultLocale {
		g.Go(func() (err error) { pageTr, err = s.store.ListPageTranslationsByLocale(gctx, locale); return })
		g.Go(func() (err error) { profileTr, err = s.store.ListProfileTranslationsByLocale(gctx, locale); return })
		g.Go(func() (err error) { navTr, err = s.store.ListNavItemTranslations(gctx); return })
		g.Go(func() (err error) { setTr, err = s.store.ListSettingsTranslations(gctx); return })
	}
	if err := g.Wait(); err != nil {
		dbError(c, err)
		return
	}

	pageText := map[int64]db.PageTranslation{}
	for _, t := range pageTr {
		pageText[t.PageID] = t
	}
	profileText := map[int64]db.ProfileTranslation{}
	for _, t := range profileTr {
		profileText[t.ProfileID] = t
	}
	navLabel := map[int64]string{}
	for _, t := range navTr {
		if t.Locale == locale {
			navLabel[t.NavItemID] = t.Label
		}
	}
	st := toSettingsDTO(settings)
	if t, ok := settingsTranslationMap(setTr)[locale]; ok {
		st.SiteName = orDefault(t.SiteName, st.SiteName)
		st.Tagline = orDefault(t.Tagline, st.Tagline)
		st.HomeDescription = orDefault(t.HomeDescription, st.HomeDescription)
	}

	out := publicSite{
		Locale:   locale,
		Settings: st,
		Pages:    make([]publicPage, 0, len(pages)),
		Profiles: make([]publicProfile, 0, len(profiles)),
		Nav:      make([]publicNav, 0, len(nav)),
	}
	for _, p := range pages {
		t := pageText[p.ID]
		out.Pages = append(out.Pages, publicPage{p.ID, p.Slug, orDefault(t.Title, p.Title), p.Hero,
			orDefault(t.Content, p.Content), int4Ptr(p.LegacyWpID)})
	}
	for _, p := range profiles {
		t := profileText[p.ID]
		ex := p.Excerpt
		if len(t.Excerpt) > 0 {
			ex = t.Excerpt
		}
		if ex == nil {
			ex = []string{}
		}
		out.Profiles = append(out.Profiles, publicProfile{p.ID, p.Slug, orDefault(t.Title, p.Title), ex, p.Thumb, p.Hero,
			orDefault(t.Content, p.Content), int4Ptr(p.LegacyWpID)})
	}
	for _, n := range nav {
		label := orDefault(navLabel[n.ID], n.Label)
		switch {
		case n.Href.Valid:
			out.Nav = append(out.Nav, publicNav{Label: label, Href: n.Href.String})
		case n.PageSlug.Valid && n.PagePublished.Valid && n.PagePublished.Bool:
			// Links to draft pages are hidden rather than left dangling.
			id := n.PageID.Int64
			// An untranslated label for a page link takes the page's own
			// translated title, so the menu matches the page it opens.
			if _, translated := navLabel[n.ID]; !translated {
				label = orDefault(pageText[id].Title, label)
			}
			out.Nav = append(out.Nav, publicNav{Label: label, Link: "/" + n.PageSlug.String, PageID: &id})
		}
	}
	// Short cache: edits show up within a minute without a deploy. The body
	// depends on the language, so shared caches must key on it.
	c.Header("Cache-Control", "public, max-age=60")
	c.Header("Vary", "Accept-Language")
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
	// Translated labels keyed by locale.
	Labels map[string]string `json:"labels"`
}

func (s *Server) listNav(c *gin.Context) {
	ctx := c.Request.Context()
	rows, err := s.store.ListNavItems(ctx)
	if err != nil {
		dbError(c, err)
		return
	}
	tr, err := s.store.ListNavItemTranslations(ctx)
	if err != nil {
		dbError(c, err)
		return
	}
	labels := map[int64]map[string]string{}
	for _, t := range tr {
		if labels[t.NavItemID] == nil {
			labels[t.NavItemID] = map[string]string{}
		}
		labels[t.NavItemID][t.Locale] = t.Label
	}
	out := make([]navDTO, len(rows))
	for i, n := range rows {
		l := labels[n.ID]
		if l == nil {
			l = map[string]string{}
		}
		d := navDTO{ID: n.ID, Label: n.Label, Href: n.Href.String, SortOrder: n.SortOrder,
			PageSlug: n.PageSlug.String, PagePublished: n.PagePublished.Bool, Labels: l}
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
	// Translated labels keyed by locale. Blank ones are dropped.
	Labels map[string]string `json:"labels"`
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
		if msg := checkLocales(it.Labels); msg != "" {
			badRequest(c, msg)
			return
		}
		for l, v := range it.Labels {
			if v = strings.TrimSpace(v); v == "" {
				delete(it.Labels, l)
			} else {
				it.Labels[l] = v
			}
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
			item, err := q.CreateNavItem(ctx, p)
			if err != nil {
				return err
			}
			for locale, label := range it.Labels {
				if err := q.CreateNavItemTranslation(ctx, db.CreateNavItemTranslationParams{
					NavItemID: item.ID, Locale: locale, Label: label,
				}); err != nil {
					return err
				}
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

// adminSettingsDTO is what the admin edits: the English settings plus their
// translations. The public site gets plain settingsDTO, already localized.
type adminSettingsDTO struct {
	settingsDTO
	Translations map[string]settingsTranslationDTO `json:"translations"`
}

func (s *Server) loadAdminSettings(ctx context.Context, q db.Querier) (adminSettingsDTO, error) {
	st, err := q.GetSettings(ctx)
	if err != nil {
		return adminSettingsDTO{}, err
	}
	tr, err := q.ListSettingsTranslations(ctx)
	if err != nil {
		return adminSettingsDTO{}, err
	}
	return adminSettingsDTO{toSettingsDTO(st), settingsTranslationMap(tr)}, nil
}

func (s *Server) getSettings(c *gin.Context) {
	out, err := s.loadAdminSettings(c.Request.Context(), s.store)
	if err != nil {
		dbError(c, err)
		return
	}
	c.JSON(http.StatusOK, out)
}

func (s *Server) updateSettings(c *gin.Context) {
	var in adminSettingsDTO
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
	if msg := checkLocales(in.Translations); msg != "" {
		badRequest(c, msg)
		return
	}
	ctx := c.Request.Context()
	by := currentUserID(c)
	var before, after adminSettingsDTO
	err := s.store.ExecTx(ctx, func(q db.Querier) error {
		var err error
		if before, err = s.loadAdminSettings(ctx, q); err != nil {
			return err
		}
		if _, err = q.UpdateSettings(ctx, db.UpdateSettingsParams{
			SiteName: in.SiteName, Tagline: strings.TrimSpace(in.Tagline),
			HomeDescription: strings.TrimSpace(in.HomeDescription),
			HomeHeaderImage: strings.TrimSpace(in.HomeHeaderImage), Logo: strings.TrimSpace(in.Logo),
			UpdatedBy: by,
		}); err != nil {
			return err
		}
		// Same rule as pages: named locales are set (or removed when blank),
		// others are left alone.
		for locale, t := range in.Translations {
			t.normalize()
			if t.empty() {
				err = q.DeleteSettingsTranslation(ctx, locale)
			} else {
				err = q.UpsertSettingsTranslation(ctx, db.UpsertSettingsTranslationParams{
					Locale: locale, SiteName: t.SiteName, Tagline: t.Tagline,
					HomeDescription: t.HomeDescription, UpdatedBy: by,
				})
			}
			if err != nil {
				return err
			}
		}
		after, err = s.loadAdminSettings(ctx, q)
		return err
	})
	if err != nil {
		dbError(c, err)
		return
	}
	s.audit(c, "update", "settings", "", gin.H{"before": before, "after": after})
	c.JSON(http.StatusOK, after)
}
