package api

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/mstoews/azma-associates/server/db/dbutil"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	"github.com/mstoews/azma-associates/server/storage"
	"github.com/mstoews/azma-associates/server/util"
)

func TestSlugifyMatchesFrontEnd(t *testing.T) {
	// Expected values are what slugify() in src/app/site-data.ts produces.
	cases := map[string]string{
		"Who We Are":        "who-we-are",
		"Vision &  Mission": "vision-mission",
		"Shigekazu Ukai":    "shigekazu-ukai",
		"  --Hello__World!": "hello-world",
		"日本語":               "",
	}
	for in, want := range cases {
		if got := Slugify(in); got != want {
			t.Errorf("Slugify(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestValidAssetURL(t *testing.T) {
	ok := []string{"", "/wp-content/a.jpg", "/media/2026/11/x.png", "https://example.com/a.jpg"}
	bad := []string{"javascript:alert(1)", "data:image/png;base64,xx", "//evil.example/a.jpg", "a.jpg"}
	for _, u := range ok {
		if !validAssetURL(u) {
			t.Errorf("validAssetURL(%q) = false, want true", u)
		}
	}
	for _, u := range bad {
		if validAssetURL(u) {
			t.Errorf("validAssetURL(%q) = true, want false", u)
		}
	}
}

func TestValidSlugReserved(t *testing.T) {
	if validSlug("admin", true) == "" {
		t.Error("admin must be reserved at top level")
	}
	if validSlug("admin", false) != "" {
		t.Error("admin is fine as a profile slug")
	}
	if validSlug("Bad Slug", true) == "" {
		t.Error("spaces must be rejected")
	}
}

// ---- integration -------------------------------------------------------
//
// Runs against a real database when TEST_DB_SOURCE is set, e.g.
//   TEST_DB_SOURCE=postgresql://cms:cms@localhost:55440/cms_test?sslmode=disable go test ./api
// The test owns that database: it rolls the schema all the way down and up.

type harness struct {
	t     *testing.T
	h     http.Handler
	token string
}

func (h *harness) do(method, path string, body any) (int, map[string]any, []byte) {
	h.t.Helper()
	var rdr *bytes.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rdr = bytes.NewReader(b)
	} else {
		rdr = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, path, rdr)
	req.Header.Set("Content-Type", "application/json")
	if h.token != "" {
		req.Header.Set("Authorization", "Bearer "+h.token)
	}
	rec := httptest.NewRecorder()
	h.h.ServeHTTP(rec, req)
	var obj map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &obj)
	return rec.Code, obj, rec.Body.Bytes()
}

func (h *harness) expect(want int, method, path string, body any) map[string]any {
	h.t.Helper()
	code, obj, raw := h.do(method, path, body)
	if code != want {
		h.t.Fatalf("%s %s: status %d, want %d: %s", method, path, code, want, raw)
	}
	return obj
}

func TestAPIFlow(t *testing.T) {
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

	hash, err := HashPassword("correct horse battery")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.CreateUser(ctx, db.CreateUserParams{Email: "Admin@Example.com", Name: "Admin", PasswordHash: hash}); err != nil {
		t.Fatal(err)
	}

	mediaDir := t.TempDir()
	media, err := storage.NewLocal(mediaDir)
	if err != nil {
		t.Fatal(err)
	}
	srv := NewServer(util.Config{
		SessionDuration: time.Hour, LoginLockoutThreshold: 3, LoginLockoutWindow: time.Minute,
		MediaDir: mediaDir, MediaURLPrefix: "/media", MediaMaxBytes: 1 << 20,
	}, store, media)
	h := &harness{t: t, h: srv.Handler()}

	// Anonymous callers cannot reach admin routes.
	h.expect(http.StatusUnauthorized, "GET", "/api/v1/admin/pages", nil)
	h.token = "not-a-real-token"
	h.expect(http.StatusUnauthorized, "GET", "/api/v1/admin/pages", nil)
	h.token = ""

	// Bad password, then lockout after the threshold.
	h.expect(http.StatusUnauthorized, "POST", "/api/v1/auth/login", map[string]string{"email": "admin@example.com", "password": "wrong password!!"})
	h.expect(http.StatusUnauthorized, "POST", "/api/v1/auth/login", map[string]string{"email": "nobody@example.com", "password": "wrong password!!"})

	// Email match is case-insensitive.
	login := h.expect(http.StatusOK, "POST", "/api/v1/auth/login", map[string]string{"email": "admin@example.com", "password": "correct horse battery"})
	h.token = login["token"].(string)
	h.expect(http.StatusOK, "GET", "/api/v1/auth/me", nil)

	// Pages: create a draft, check it is hidden publicly, publish it.
	page := h.expect(http.StatusCreated, "POST", "/api/v1/admin/pages", map[string]any{
		"title": "Our Team", "content": "<p>Hi</p>", "hero": "/media/x.jpg", "published": false,
	})
	if page["slug"] != "our-team" {
		t.Fatalf("slug = %v", page["slug"])
	}
	pid := int(page["id"].(float64))
	h.expect(http.StatusBadRequest, "POST", "/api/v1/admin/pages", map[string]any{"title": "Admin"})
	h.expect(http.StatusBadRequest, "POST", "/api/v1/admin/pages", map[string]any{"title": "X", "hero": "javascript:alert(1)"})
	h.expect(http.StatusConflict, "POST", "/api/v1/admin/pages", map[string]any{"title": "Our Team"})

	h.expect(http.StatusOK, "PUT", "/api/v1/admin/nav", map[string]any{"items": []map[string]any{
		{"label": "Team", "pageId": pid}, {"label": "JP", "href": "https://azma-associates.jp/"},
	}})
	h.expect(http.StatusBadRequest, "PUT", "/api/v1/admin/nav", map[string]any{"items": []map[string]any{{"label": "Bad", "href": "javascript:x"}}})

	site := h.expect(http.StatusOK, "GET", "/api/v1/site", nil)
	if n := len(site["pages"].([]any)); n != 0 {
		t.Fatalf("draft page leaked to public site (%d pages)", n)
	}
	if n := len(site["nav"].([]any)); n != 1 {
		t.Fatalf("nav to a draft page should be hidden; got %d items", n)
	}

	h.expect(http.StatusOK, "PUT", "/api/v1/admin/pages/"+itoa(pid), map[string]any{
		"title": "Our Team", "slug": "team", "content": "<p>Hello</p>", "published": true,
	})
	site = h.expect(http.StatusOK, "GET", "/api/v1/site", nil)
	pages := site["pages"].([]any)
	if len(pages) != 1 || pages[0].(map[string]any)["slug"] != "team" {
		t.Fatalf("published page missing: %v", pages)
	}
	if nav := site["nav"].([]any); len(nav) != 2 || nav[0].(map[string]any)["link"] != "/team" {
		t.Fatalf("nav = %v", nav)
	}

	// Profiles keep their excerpt lines and may use slugs reserved at top level.
	prof := h.expect(http.StatusCreated, "POST", "/api/v1/admin/profiles", map[string]any{
		"title": "Jane Doe", "slug": "admin", "excerpt": []string{"ジェーン", " Consultant ", ""}, "published": true,
	})
	if ex := prof["excerpt"].([]any); len(ex) != 2 || ex[1] != "Consultant" {
		t.Fatalf("excerpt = %v", ex)
	}

	// Settings.
	h.expect(http.StatusOK, "PUT", "/api/v1/admin/settings", map[string]any{"siteName": "AZMA", "tagline": "t", "logo": "/media/l.png"})
	h.expect(http.StatusBadRequest, "PUT", "/api/v1/admin/settings", map[string]any{"siteName": ""})

	// Media: PNG accepted and served; a text file is rejected regardless of its name.
	var img bytes.Buffer
	m := image.NewRGBA(image.Rect(0, 0, 3, 2))
	m.Set(0, 0, color.White)
	_ = png.Encode(&img, m)
	code, up := uploadFile(t, h, "photo of me.PNG", img.Bytes())
	if code != http.StatusCreated {
		t.Fatalf("upload: %d %v", code, up)
	}
	if up["width"].(float64) != 3 || up["height"].(float64) != 2 {
		t.Fatalf("dimensions = %v x %v", up["width"], up["height"])
	}
	url := up["url"].(string)
	req := httptest.NewRequest("GET", url, nil)
	rec := httptest.NewRecorder()
	h.h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK || rec.Body.Len() != img.Len() || rec.Header().Get("Content-Type") != "image/png" {
		t.Fatalf("GET %s: %d (%d bytes, %s)", url, rec.Code, rec.Body.Len(), rec.Header().Get("Content-Type"))
	}
	// Conditional GET and traversal attempts.
	req = httptest.NewRequest("GET", url, nil)
	req.Header.Set("If-None-Match", rec.Header().Get("ETag"))
	rec2 := httptest.NewRecorder()
	h.h.ServeHTTP(rec2, req)
	if rec2.Code != http.StatusNotModified {
		t.Fatalf("conditional GET: %d", rec2.Code)
	}
	for _, bad := range []string{"/media/../app.env", "/media/%2e%2e/app.env", "/media/2026/.upload-x"} {
		rec3 := httptest.NewRecorder()
		h.h.ServeHTTP(rec3, httptest.NewRequest("GET", bad, nil))
		if rec3.Code == http.StatusOK {
			t.Fatalf("GET %s served a file", bad)
		}
	}
	if code, _ := uploadFile(t, h, "evil.png", []byte("<svg onload=alert(1)>")); code != http.StatusUnsupportedMediaType {
		t.Fatalf("text upload status %d, want 415", code)
	}

	// A file in use cannot be deleted without force.
	h.expect(http.StatusOK, "PUT", "/api/v1/admin/settings", map[string]any{"siteName": "AZMA", "logo": url})
	mid := itoa(int(up["id"].(float64)))
	h.expect(http.StatusConflict, "DELETE", "/api/v1/admin/media/"+mid, nil)
	h.expect(http.StatusNoContent, "DELETE", "/api/v1/admin/media/"+mid+"?force=1", nil)
	files, _ := filepath.Glob(filepath.Join(mediaDir, "*", "*", "*"))
	if len(files) != 0 {
		t.Fatalf("file not removed from disk: %v", files)
	}

	// Users: the last admin cannot be removed; a second one can be managed.
	me := login["user"].(map[string]any)["id"].(string)
	h.expect(http.StatusBadRequest, "DELETE", "/api/v1/admin/users/"+me, nil)
	h.expect(http.StatusBadRequest, "POST", "/api/v1/admin/users", map[string]any{"email": "b@example.com", "password": "short"})
	u2 := h.expect(http.StatusCreated, "POST", "/api/v1/admin/users", map[string]any{"email": "b@example.com", "name": "B", "password": "another long password"})
	h.expect(http.StatusConflict, "POST", "/api/v1/admin/users", map[string]any{"email": "B@example.com", "password": "another long password"})

	// Second admin signs in, gets disabled, and their session dies.
	admin1 := h.token
	h.token = ""
	l2 := h.expect(http.StatusOK, "POST", "/api/v1/auth/login", map[string]string{"email": "b@example.com", "password": "another long password"})
	tok2 := l2["token"].(string)
	h.token = admin1
	h.expect(http.StatusOK, "PUT", "/api/v1/admin/users/"+u2["id"].(string), map[string]any{"name": "B", "disabled": true})
	h.token = tok2
	h.expect(http.StatusUnauthorized, "GET", "/api/v1/auth/me", nil)

	// Lockout: threshold is 3 in this config.
	h.token = ""
	for i := 0; i < 3; i++ {
		h.expect(http.StatusUnauthorized, "POST", "/api/v1/auth/login", map[string]string{"email": "admin@example.com", "password": "wrong password!!"})
	}
	h.expect(http.StatusTooManyRequests, "POST", "/api/v1/auth/login", map[string]string{"email": "admin@example.com", "password": "correct horse battery"})

	// The existing session still works; logout revokes it.
	h.token = admin1
	audit := h.expect(http.StatusOK, "GET", "/api/v1/admin/audit?limit=5", nil)
	_ = audit
	h.expect(http.StatusNoContent, "POST", "/api/v1/auth/logout", nil)
	h.expect(http.StatusUnauthorized, "GET", "/api/v1/auth/me", nil)
}

func uploadFile(t *testing.T, h *harness, name string, data []byte) (int, map[string]any) {
	t.Helper()
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	fw, _ := w.CreateFormFile("file", name)
	_, _ = fw.Write(data)
	_ = w.WriteField("alt", "alt text")
	_ = w.Close()
	req := httptest.NewRequest("POST", "/api/v1/admin/media", &buf)
	req.Header.Set("Content-Type", w.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+h.token)
	rec := httptest.NewRecorder()
	h.h.ServeHTTP(rec, req)
	var obj map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &obj)
	return rec.Code, obj
}

func itoa(i int) string { b, _ := json.Marshal(i); return string(b) }
