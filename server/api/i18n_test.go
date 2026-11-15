package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/mstoews/azma-associates/server/db/dbutil"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	"github.com/mstoews/azma-associates/server/storage"
	"github.com/mstoews/azma-associates/server/util"
)

func TestAcceptedLanguages(t *testing.T) {
	cases := map[string][]string{
		"":                           {},
		"ja":                         {"ja"},
		"ja-JP,ja;q=0.9,en-US;q=0.8": {"ja", "en"},
		"en-GB;q=0.5, ja;q=0.8":      {"ja", "en"},
		"fr, *;q=0.1":                {"fr"},
		"ja;q=0, en":                 {"en"},
		"EN_us":                      {"en"},
	}
	for header, want := range cases {
		if got := acceptedLanguages(header); !slices.Equal(got, want) {
			t.Errorf("acceptedLanguages(%q) = %v, want %v", header, got, want)
		}
	}
}

func TestRequestLocale(t *testing.T) {
	gin.SetMode(gin.TestMode)
	cases := []struct {
		query, header, want string
	}{
		{"", "", "en"},
		{"", "ja-JP,en;q=0.8", "ja"},
		{"", "en-US,ja;q=0.8", "en"}, // English first means English
		{"", "fr-FR,ja;q=0.5", "ja"}, // first supported one
		{"ja", "en", "ja"},           // ?lang= wins
		{"en", "ja", "en"},
		{"fr", "ja", "en"}, // an unsupported ?lang= is an explicit choice: English
	}
	for _, tc := range cases {
		rec := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(rec)
		path := "/api/v1/site"
		if tc.query != "" {
			path += "?lang=" + tc.query
		}
		c.Request = httptest.NewRequest("GET", path, nil)
		if tc.header != "" {
			c.Request.Header.Set("Accept-Language", tc.header)
		}
		if got := requestLocale(c); got != tc.want {
			t.Errorf("lang=%q Accept-Language=%q: got %q, want %q", tc.query, tc.header, got, tc.want)
		}
	}
}

// TestContentTranslations runs against TEST_DB_SOURCE like TestAPIFlow.
func TestContentTranslations(t *testing.T) {
	dsn := os.Getenv("TEST_DB_SOURCE")
	if dsn == "" {
		t.Skip("TEST_DB_SOURCE not set")
	}
	_ = dbutil.MigrateDown(dsn, 0)
	if err := dbutil.MigrateUp(dsn); err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	pool, err := dbutil.Connect(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	store := db.NewStore(pool)
	hash, _ := HashPassword("correct horse battery")
	if _, err := store.CreateUser(ctx, db.CreateUserParams{Email: "admin@example.com", Name: "Admin", PasswordHash: hash, Role: "admin"}); err != nil {
		t.Fatal(err)
	}
	mediaDir := t.TempDir()
	media, _ := storage.NewLocal(mediaDir)
	srv := NewServer(util.Config{
		SessionDuration: time.Hour, LoginLockoutThreshold: 5, LoginLockoutWindow: time.Minute,
		MediaDir: mediaDir, MediaURLPrefix: "/media", MediaMaxBytes: 1 << 20,
	}, store, media)
	h := &harness{t: t, h: srv.Handler()}
	login := h.expect(http.StatusOK, "POST", "/api/v1/auth/login", map[string]string{"email": "admin@example.com", "password": "correct horse battery"})
	h.token = login["token"].(string)

	// A page with a full Japanese translation, and one left in English.
	page := h.expect(http.StatusCreated, "POST", "/api/v1/admin/pages", map[string]any{
		"title": "Who We Are", "content": "<p>About us</p>", "published": true,
		"translations": map[string]any{"ja": map[string]any{"title": " 会社概要 ", "content": "<p>私たちについて</p>"}},
	})
	pid := int(page["id"].(float64))
	ja := page["translations"].(map[string]any)["ja"].(map[string]any)
	if ja["title"] != "会社概要" {
		t.Fatalf("translated title not trimmed/saved: %v", ja)
	}
	h.expect(http.StatusCreated, "POST", "/api/v1/admin/pages", map[string]any{"title": "Search Process", "content": "<p>How</p>", "published": true})

	// Unsupported locales are rejected.
	h.expect(http.StatusBadRequest, "POST", "/api/v1/admin/pages", map[string]any{
		"title": "X", "translations": map[string]any{"fr": map[string]any{"title": "Qui"}},
	})

	// Updating without a translations map leaves translations alone.
	upd := h.expect(http.StatusOK, "PUT", "/api/v1/admin/pages/"+itoa(pid), map[string]any{
		"slug": "who-we-are", "title": "Who We Are", "content": "<p>About us, updated</p>", "published": true,
	})
	if _, ok := upd["translations"].(map[string]any)["ja"]; !ok {
		t.Fatal("update without translations dropped the Japanese text")
	}

	// A profile with translated name and card lines only; content falls back.
	prof := h.expect(http.StatusCreated, "POST", "/api/v1/admin/profiles", map[string]any{
		"title": "Kaori Semba", "excerpt": []string{"仙波 かおり", "Managing Director", "Tokyo"}, "content": "<p>Bio</p>", "published": true,
		"translations": map[string]any{"ja": map[string]any{"title": "仙波 かおり", "excerpt": []string{"Kaori Semba", "代表取締役", " ", "東京"}}},
	})
	profID := int(prof["id"].(float64))
	if ex := prof["translations"].(map[string]any)["ja"].(map[string]any)["excerpt"].([]any); len(ex) != 3 {
		t.Fatalf("blank card lines should be dropped: %v", ex)
	}

	// Menu with one translated label and one page link left to inherit the page title.
	h.expect(http.StatusOK, "PUT", "/api/v1/admin/nav", map[string]any{"items": []map[string]any{
		{"label": "Who We Are", "pageId": pid},
		{"label": "Japanese site", "href": "https://azma-associates.jp/", "labels": map[string]string{"ja": "日本語サイト"}},
	}})
	_, _, raw := h.do("PUT", "/api/v1/admin/nav", map[string]any{"items": []map[string]any{
		{"label": "X", "href": "https://example.com/", "labels": map[string]string{"de": "Y"}},
	}})
	if !strings.Contains(string(raw), "unsupported language") {
		t.Fatalf("unsupported nav locale should be rejected: %s", raw)
	}

	// Settings with a partial translation.
	settings := h.expect(http.StatusOK, "GET", "/api/v1/admin/settings", nil)
	settings["siteName"] = "AZMA & Associates"
	settings["tagline"] = "We are an APAC professional recruitment firm."
	settings["translations"] = map[string]any{"ja": map[string]any{"tagline": "アジア太平洋地域の人材紹介会社です。"}}
	saved := h.expect(http.StatusOK, "PUT", "/api/v1/admin/settings", settings)
	if saved["translations"].(map[string]any)["ja"].(map[string]any)["tagline"] == "" {
		t.Fatal("settings translation not saved")
	}

	// ---- public site in English (default) and Japanese ----
	h.token = ""
	en := h.expect(http.StatusOK, "GET", "/api/v1/site", nil)
	if en["locale"] != "en" || en["settings"].(map[string]any)["tagline"] != "We are an APAC professional recruitment firm." {
		t.Fatalf("English site wrong: locale=%v settings=%v", en["locale"], en["settings"])
	}
	if _, leaked := en["settings"].(map[string]any)["translations"]; leaked {
		t.Fatal("public settings must not carry the translations map")
	}

	rec := h.raw("GET", "/api/v1/site", "")
	if rec.Header().Get("Vary") != "Accept-Language" {
		t.Fatalf("Vary = %q", rec.Header().Get("Vary"))
	}

	for _, req := range []struct{ path, header string }{
		{"/api/v1/site?lang=ja", ""},
		{"/api/v1/site", "ja-JP,ja;q=0.9,en;q=0.8"},
	} {
		r := httptest.NewRequest("GET", req.path, nil)
		if req.header != "" {
			r.Header.Set("Accept-Language", req.header)
		}
		w := httptest.NewRecorder()
		srv.Handler().ServeHTTP(w, r)
		var site publicSite
		if err := json.Unmarshal(w.Body.Bytes(), &site); err != nil {
			t.Fatal(err)
		}
		if site.Locale != "ja" {
			t.Fatalf("%s: locale = %q", req.path, site.Locale)
		}
		if site.Settings.Tagline != "アジア太平洋地域の人材紹介会社です。" || site.Settings.SiteName != "AZMA & Associates" {
			t.Errorf("settings should mix translated tagline with English name: %+v", site.Settings)
		}
		titles := map[string]string{}
		for _, p := range site.Pages {
			titles[p.Slug] = p.Title
		}
		if titles["who-we-are"] != "会社概要" || titles["search-process"] != "Search Process" {
			t.Errorf("page titles: %v", titles)
		}
		for _, p := range site.Pages {
			if p.Slug == "who-we-are" && p.Content != "<p>私たちについて</p>" {
				t.Errorf("translated content not served: %q", p.Content)
			}
		}
		if len(site.Profiles) != 1 || site.Profiles[0].Title != "仙波 かおり" ||
			site.Profiles[0].Content != "<p>Bio</p>" || site.Profiles[0].Excerpt[1] != "代表取締役" {
			t.Errorf("profile: %+v", site.Profiles)
		}
		if len(site.Nav) != 2 || site.Nav[0].Label != "会社概要" || site.Nav[1].Label != "日本語サイト" {
			t.Errorf("nav: %+v", site.Nav)
		}
	}

	// Clearing every field of a translation removes it.
	h.token = login["token"].(string)
	cleared := h.expect(http.StatusOK, "PUT", "/api/v1/admin/profiles/"+itoa(profID), map[string]any{
		"slug": "kaori-semba", "title": "Kaori Semba", "excerpt": []string{"仙波 かおり"}, "content": "<p>Bio</p>", "published": true,
		"translations": map[string]any{"ja": map[string]any{"title": "", "excerpt": []string{}, "content": " "}},
	})
	if len(cleared["translations"].(map[string]any)) != 0 {
		t.Fatalf("empty translation should be deleted: %v", cleared["translations"])
	}

	// Deleting a page takes its translations with it.
	h.expect(http.StatusNoContent, "DELETE", "/api/v1/admin/pages/"+itoa(pid), nil)
	if rows, _ := store.ListPageTranslations(ctx); len(rows) != 0 {
		t.Fatalf("translations left behind: %v", rows)
	}
}
