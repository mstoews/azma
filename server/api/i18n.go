package api

import (
	"context"
	"slices"
	"sort"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
)

// Content is written in English, which lives in the original tables and is
// the fallback for every field. These are the other languages it can be
// translated into. Adding one here is all the API needs; the tables accept
// any two-letter code.
var supportedLocales = []string{"ja"}

const defaultLocale = "en"

func isSupportedLocale(l string) bool { return slices.Contains(supportedLocales, l) }

// requestLocale picks the language to serve: an explicit ?lang= wins, then
// the first supported language in Accept-Language, then English. Region
// subtags are ignored ("ja-JP" is "ja").
func requestLocale(c *gin.Context) string {
	if l := baseLanguage(c.Query("lang")); l != "" {
		if isSupportedLocale(l) {
			return l
		}
		return defaultLocale
	}
	for _, l := range acceptedLanguages(c.GetHeader("Accept-Language")) {
		if l == defaultLocale || isSupportedLocale(l) {
			return l
		}
	}
	return defaultLocale
}

func baseLanguage(tag string) string {
	tag = strings.ToLower(strings.TrimSpace(tag))
	if i := strings.IndexAny(tag, "-_"); i >= 0 {
		tag = tag[:i]
	}
	return tag
}

// acceptedLanguages returns the languages in an Accept-Language header,
// most preferred first. Entries with q=0 are dropped.
func acceptedLanguages(header string) []string {
	type entry struct {
		lang string
		q    float64
		pos  int
	}
	var entries []entry
	for i, part := range strings.Split(header, ",") {
		fields := strings.Split(part, ";")
		lang := baseLanguage(fields[0])
		if lang == "" || lang == "*" {
			continue
		}
		q := 1.0
		for _, f := range fields[1:] {
			if v, ok := strings.CutPrefix(strings.TrimSpace(f), "q="); ok {
				if parsed, err := strconv.ParseFloat(v, 64); err == nil {
					q = parsed
				}
			}
		}
		if q > 0 {
			entries = append(entries, entry{lang, q, i})
		}
	}
	sort.SliceStable(entries, func(a, b int) bool { return entries[a].q > entries[b].q })
	out := make([]string, 0, len(entries))
	for _, e := range entries {
		if !slices.Contains(out, e.lang) {
			out = append(out, e.lang)
		}
	}
	return out
}

func orDefault(translated, fallback string) string {
	if strings.TrimSpace(translated) == "" {
		return fallback
	}
	return translated
}

// ---- DTOs and validation -------------------------------------------------

type pageTranslationDTO struct {
	Title   string `json:"title"`
	Content string `json:"content"`
}

type profileTranslationDTO struct {
	Title   string   `json:"title"`
	Excerpt []string `json:"excerpt"`
	Content string   `json:"content"`
}

type settingsTranslationDTO struct {
	SiteName        string `json:"siteName"`
	Tagline         string `json:"tagline"`
	HomeDescription string `json:"homeDescription"`
}

func checkLocales[T any](m map[string]T) string {
	for l := range m {
		if !isSupportedLocale(l) {
			return "unsupported language '" + l + "'"
		}
	}
	return ""
}

func (t *pageTranslationDTO) normalize() string {
	t.Title = strings.TrimSpace(t.Title)
	switch {
	case len(t.Title) > 200:
		return "translated title is too long"
	case len(t.Content) > maxContentBytes:
		return "translated content is too large"
	}
	return ""
}

func (t pageTranslationDTO) empty() bool {
	return t.Title == "" && strings.TrimSpace(t.Content) == ""
}

func (t *profileTranslationDTO) normalize() string {
	p := pageTranslationDTO{t.Title, t.Content}
	if msg := p.normalize(); msg != "" {
		return msg
	}
	t.Title = p.Title
	if len(t.Excerpt) > 10 {
		return "translated card text has too many lines"
	}
	t.Excerpt = cleanLines(t.Excerpt)
	return ""
}

func (t profileTranslationDTO) empty() bool {
	return t.Title == "" && len(t.Excerpt) == 0 && strings.TrimSpace(t.Content) == ""
}

func (t *settingsTranslationDTO) normalize() string {
	t.SiteName = strings.TrimSpace(t.SiteName)
	t.Tagline = strings.TrimSpace(t.Tagline)
	t.HomeDescription = strings.TrimSpace(t.HomeDescription)
	return ""
}

func (t settingsTranslationDTO) empty() bool {
	return t.SiteName == "" && t.Tagline == "" && t.HomeDescription == ""
}

func cleanLines(lines []string) []string {
	out := make([]string, 0, len(lines))
	for _, l := range lines {
		if l = strings.TrimSpace(l); l != "" {
			out = append(out, l)
		}
	}
	return out
}

// ---- saving ----------------------------------------------------------------
//
// A translations map in a request sets the locales it names: a locale with
// every field empty is removed, others are written. Locales not named are left
// as they are, and a request without the map changes no translations.

func savePageTranslations(ctx context.Context, q db.Querier, pageID int64, by uuid.NullUUID, m map[string]pageTranslationDTO) error {
	for locale, t := range m {
		var err error
		if t.empty() {
			err = q.DeletePageTranslation(ctx, db.DeletePageTranslationParams{PageID: pageID, Locale: locale})
		} else {
			err = q.UpsertPageTranslation(ctx, db.UpsertPageTranslationParams{
				PageID: pageID, Locale: locale, Title: t.Title, Content: t.Content, UpdatedBy: by,
			})
		}
		if err != nil {
			return err
		}
	}
	return nil
}

func saveProfileTranslations(ctx context.Context, q db.Querier, profileID int64, by uuid.NullUUID, m map[string]profileTranslationDTO) error {
	for locale, t := range m {
		var err error
		if t.empty() {
			err = q.DeleteProfileTranslation(ctx, db.DeleteProfileTranslationParams{ProfileID: profileID, Locale: locale})
		} else {
			err = q.UpsertProfileTranslation(ctx, db.UpsertProfileTranslationParams{
				ProfileID: profileID, Locale: locale, Title: t.Title, Excerpt: t.Excerpt, Content: t.Content, UpdatedBy: by,
			})
		}
		if err != nil {
			return err
		}
	}
	return nil
}

// ---- loading ---------------------------------------------------------------

func pageTranslationMap(rows []db.PageTranslation) map[string]pageTranslationDTO {
	m := make(map[string]pageTranslationDTO, len(rows))
	for _, r := range rows {
		m[r.Locale] = pageTranslationDTO{r.Title, r.Content}
	}
	return m
}

func profileTranslationMap(rows []db.ProfileTranslation) map[string]profileTranslationDTO {
	m := make(map[string]profileTranslationDTO, len(rows))
	for _, r := range rows {
		ex := r.Excerpt
		if ex == nil {
			ex = []string{}
		}
		m[r.Locale] = profileTranslationDTO{r.Title, ex, r.Content}
	}
	return m
}

func groupPageTranslations(rows []db.PageTranslation) map[int64][]db.PageTranslation {
	g := map[int64][]db.PageTranslation{}
	for _, r := range rows {
		g[r.PageID] = append(g[r.PageID], r)
	}
	return g
}

func groupProfileTranslations(rows []db.ProfileTranslation) map[int64][]db.ProfileTranslation {
	g := map[int64][]db.ProfileTranslation{}
	for _, r := range rows {
		g[r.ProfileID] = append(g[r.ProfileID], r)
	}
	return g
}

func settingsTranslationMap(rows []db.SiteSettingsTranslation) map[string]settingsTranslationDTO {
	m := make(map[string]settingsTranslationDTO, len(rows))
	for _, r := range rows {
		m[r.Locale] = settingsTranslationDTO{r.SiteName, r.Tagline, r.HomeDescription}
	}
	return m
}
