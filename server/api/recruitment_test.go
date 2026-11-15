package api

import (
	"bytes"
	"context"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/mstoews/azma-associates/server/db/dbutil"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	"github.com/mstoews/azma-associates/server/storage"
	"github.com/mstoews/azma-associates/server/util"
)

func TestDetectResumeType(t *testing.T) {
	pdf := []byte("%PDF-1.7\nstuff")
	docx := append([]byte("PK\x03\x04"), make([]byte, 20)...)
	doc := append([]byte{0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1}, make([]byte, 20)...)

	cases := []struct {
		name string
		data []byte
		file string
		mime string
		ok   bool
	}{
		{"pdf", pdf, "cv.pdf", mimePDF, true},
		{"pdf without an extension", pdf, "cv", mimePDF, true},
		{"pdf named .docx", pdf, "cv.docx", "", false},
		{"docx", docx, "履歴書.docx", mimeDOCX, true},
		{"doc", doc, "cv.DOC", mimeDOC, true},
		{"zip named .docx is accepted", docx, "cv.docx", mimeDOCX, true},
		{"html named .pdf", []byte("<script>alert(1)</script>"), "cv.pdf", "", false},
		{"png", []byte("\x89PNG\r\n\x1a\n"), "cv.png", "", false},
		{"empty", nil, "cv.pdf", "", false},
	}
	for _, tc := range cases {
		mime, _, ok := detectResumeType(tc.data, tc.file)
		if ok != tc.ok || mime != tc.mime {
			t.Errorf("%s: got (%q, %v), want (%q, %v)", tc.name, mime, ok, tc.mime, tc.ok)
		}
	}
}

func TestJobInputValidation(t *testing.T) {
	base := func() jobInput {
		return jobInput{Title: "Portfolio Manager", Company: "Nippon Asset", Sector: "Asset Management"}
	}
	min, max := int32(20000000), int32(10000000)

	in := base()
	if msg := in.normalize(); msg != "" {
		t.Fatalf("a minimal draft should be valid, got %q", msg)
	}
	if in.status() != "draft" {
		t.Errorf("status without submit = %q", in.status())
	}

	in = base()
	in.Submit = true
	if msg := in.normalize(); msg == "" {
		t.Error("a posting submitted for review needs a description")
	}

	in = base()
	in.Sector = "Fintech"
	if msg := in.normalize(); msg == "" {
		t.Error("an unknown sector must be refused")
	}

	in = base()
	in.SalaryMin, in.SalaryMax, in.SalaryCurrency = &min, &max, "JPY"
	if msg := in.normalize(); msg == "" {
		t.Error("a maximum below the minimum must be refused")
	}

	in = base()
	in.SalaryMin = &max
	if msg := in.normalize(); msg == "" {
		t.Error("a salary without a currency must be refused")
	}

	in = base()
	in.SalaryMin, in.SalaryCurrency = &max, "jpy"
	if msg := in.normalize(); msg != "" {
		t.Errorf("a lowercase currency should normalize, got %q", msg)
	}
}

func TestCleanList(t *testing.T) {
	got := cleanList([]string{" Equities ", "", "Equities", "Fixed Income", "  "})
	if len(got) != 2 || got[0] != "Equities" || got[1] != "Fixed Income" {
		t.Fatalf("cleanList = %#v", got)
	}
	long := make([]string, 30)
	for i := range long {
		long[i] = "role-" + strconv.Itoa(i)
	}
	if n := len(cleanList(long)); n != maxListEntries {
		t.Errorf("cleanList capped at %d, want %d", n, maxListEntries)
	}
}

// ---- integration -------------------------------------------------------
//
//	TEST_DB_SOURCE=postgresql://cms:cms@localhost:55440/cms_test?sslmode=disable go test ./api

func TestRecruitmentFlow(t *testing.T) {
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

	hash, err := HashPassword("consultant password")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.CreateUser(ctx, db.CreateUserParams{
		Email: "consultant@azma-associates.com", Name: "Consultant", PasswordHash: hash, Role: "admin",
	}); err != nil {
		t.Fatal(err)
	}

	mediaDir := t.TempDir()
	media, err := storage.NewLocal(mediaDir)
	if err != nil {
		t.Fatal(err)
	}
	srv := NewServer(util.Config{
		SessionDuration: time.Hour, LoginLockoutThreshold: 5, LoginLockoutWindow: time.Minute,
		MediaDir: mediaDir, MediaURLPrefix: "/media", MediaMaxBytes: 1 << 20,
	}, store, media)
	h := &harness{t: t, h: srv.Handler()}

	// ---- sign-up -------------------------------------------------------

	h.expect(http.StatusBadRequest, "POST", "/api/v1/auth/register", map[string]any{
		"email": "someone@example.com", "password": "short", "role": "candidate", "name": "A",
	})
	h.expect(http.StatusBadRequest, "POST", "/api/v1/auth/register", map[string]any{
		"email": "someone@example.com", "password": "a long enough password", "role": "admin", "name": "A",
	})
	cand := h.expect(http.StatusCreated, "POST", "/api/v1/auth/register", map[string]any{
		"email": "kenji@example.com", "password": "a long enough password", "role": "candidate", "name": "Kenji Watanabe",
	})
	candToken := cand["token"].(string)
	if role := cand["user"].(map[string]any)["role"]; role != "candidate" {
		t.Fatalf("registered role = %v", role)
	}
	h.expect(http.StatusConflict, "POST", "/api/v1/auth/register", map[string]any{
		"email": "Kenji@example.com", "password": "a long enough password", "role": "candidate", "name": "Dup",
	})
	emp := h.expect(http.StatusCreated, "POST", "/api/v1/auth/register", map[string]any{
		"email": "hr@nippon-asset.example", "password": "another long password", "role": "employer",
		"name": "Aiko Tanaka", "company": "Nippon Asset Management",
	})
	empToken := emp["token"].(string)

	// Registration signs the account in, and the same credentials work at
	// /auth/login (which used to refuse anyone who was not an administrator).
	h.token = candToken
	h.expect(http.StatusOK, "GET", "/api/v1/auth/me", nil)
	h.token = ""
	relogin := h.expect(http.StatusOK, "POST", "/api/v1/auth/login", map[string]string{
		"email": "kenji@example.com", "password": "a long enough password",
	})
	candToken = relogin["token"].(string)

	// ---- role gates ----------------------------------------------------

	h.token = candToken
	h.expect(http.StatusForbidden, "GET", "/api/v1/employer/me", nil)
	h.expect(http.StatusForbidden, "GET", "/api/v1/admin/jobs", nil)
	h.token = empToken
	h.expect(http.StatusForbidden, "GET", "/api/v1/candidate/me", nil)
	h.token = ""
	h.expect(http.StatusUnauthorized, "GET", "/api/v1/candidate/me", nil)

	// ---- the candidate's profile and resume ----------------------------

	h.token = candToken
	me := h.expect(http.StatusOK, "GET", "/api/v1/candidate/me", nil)
	if p := me["profile"].(map[string]any); p["fullName"] != "Kenji Watanabe" || p["submitted"] != false {
		t.Fatalf("new candidate profile = %v", p)
	}
	if n := len(me["resumes"].([]any)); n != 0 {
		t.Fatalf("new account has %d resumes", n)
	}

	h.expect(http.StatusBadRequest, "PUT", "/api/v1/candidate/profile", map[string]any{"fullName": ""})
	h.expect(http.StatusBadRequest, "PUT", "/api/v1/candidate/profile", map[string]any{
		"fullName": "Kenji Watanabe", "sectors": []string{"Crypto Mining"},
	})
	prof := h.expect(http.StatusOK, "PUT", "/api/v1/candidate/profile", map[string]any{
		"fullName": " Kenji Watanabe ", "headline": "Equity PM, Tokyo",
		"location": "Tokyo", "currentEmployer": "Daiwa", "currentTitle": "Senior Analyst",
		"yearsExperience": 12, "sectors": []string{"Asset Management", "Asset Management", "Securities"},
		"desiredRoles": []string{"Portfolio Manager"}, "languages": []string{"Japanese", "English"},
		"openToOffers": true,
	})
	if prof["fullName"] != "Kenji Watanabe" {
		t.Errorf("fullName not trimmed: %v", prof["fullName"])
	}
	if s := prof["sectors"].([]any); len(s) != 2 {
		t.Errorf("duplicate sectors not collapsed: %v", s)
	}

	// Nothing reaches a consultant without a resume on file.
	h.expect(http.StatusBadRequest, "POST", "/api/v1/candidate/profile/submit", map[string]any{"submitted": true})

	if code, body := uploadResume(t, h, "cv.png", []byte("\x89PNG\r\n\x1a\n")); code != http.StatusUnsupportedMediaType {
		t.Fatalf("a PNG resume was accepted: %d %v", code, body)
	}
	code, up := uploadResume(t, h, "Kenji Watanabe CV.pdf", []byte("%PDF-1.7\nmy experience"))
	if code != http.StatusCreated {
		t.Fatalf("resume upload: %d %v", code, up)
	}
	resumeID := int64(up["id"].(float64))
	if up["mimeType"] != mimePDF || up["filename"] != "Kenji Watanabe CV.pdf" {
		t.Fatalf("resume = %v", up)
	}

	// The owner can read it back; it is not on a public path.
	dl := "/api/v1/resumes/" + strconv.FormatInt(resumeID, 10) + "/file"
	rec := h.raw("GET", dl, candToken)
	if rec.Code != http.StatusOK || rec.Body.String() != "%PDF-1.7\nmy experience" {
		t.Fatalf("own resume download: %d %q", rec.Code, rec.Body.String())
	}
	if cc := rec.Header().Get("Cache-Control"); cc != "private, no-store" {
		t.Errorf("resume Cache-Control = %q", cc)
	}
	if rec := h.raw("GET", dl, ""); rec.Code != http.StatusUnauthorized {
		t.Errorf("anonymous resume download: %d", rec.Code)
	}
	if rec := h.raw("GET", dl, empToken); rec.Code != http.StatusNotFound {
		t.Errorf("an employer could read a resume directly: %d", rec.Code)
	}

	submitted := h.expect(http.StatusOK, "POST", "/api/v1/candidate/profile/submit", map[string]any{"submitted": true})
	if submitted["submitted"] != true || submitted["submittedAt"] == nil {
		t.Fatalf("submit = %v", submitted)
	}

	// ---- the employer's posting ----------------------------------------

	h.token = empToken
	h.expect(http.StatusOK, "PUT", "/api/v1/employer/profile", map[string]any{
		"company": "Nippon Asset Management", "contactName": "Aiko Tanaka",
		"contactRole": "Head of HR", "location": "Tokyo",
	})
	h.expect(http.StatusBadRequest, "POST", "/api/v1/employer/jobs", map[string]any{"title": "", "company": "X"})
	draft := h.expect(http.StatusCreated, "POST", "/api/v1/employer/jobs", map[string]any{
		"title": "Fixed Income Analyst", "company": "Nippon Asset Management", "location": "Tokyo",
		"sector": "Asset Management", "description": "A draft we are still writing.",
	})
	if draft["status"] != "draft" {
		t.Fatalf("unsubmitted posting status = %v", draft["status"])
	}
	posting := h.expect(http.StatusCreated, "POST", "/api/v1/employer/jobs", map[string]any{
		"title": "Portfolio Manager, Japan Equities", "company": "Nippon Asset Management",
		"location": "Tokyo", "sector": "Asset Management", "employmentType": "full_time",
		"description":  "Manage a long-only Japan equity book for institutional clients, reporting to the CIO.",
		"requirements": "10+ years running Japanese equities at an asset manager.",
		"salaryMin":    25000000, "salaryMax": 35000000, "salaryCurrency": "JPY",
		"submit": true,
	})
	jobID := int64(posting["id"].(float64))
	if posting["status"] != "pending" {
		t.Fatalf("submitted posting status = %v", posting["status"])
	}
	confidential := h.expect(http.StatusCreated, "POST", "/api/v1/employer/jobs", map[string]any{
		"title": "Head of Alternatives", "company": "Nippon Asset Management", "confidential": true,
		"location": "Singapore", "sector": "Alternative Investment Management",
		"description": "A confidential search for a client who does not want to be named publicly.",
		"submit":      true,
	})
	confidentialID := int64(confidential["id"].(float64))

	// Nothing is on the board until a consultant approves it.
	h.token = ""
	board := h.expect(http.StatusOK, "GET", "/api/v1/jobs", nil)
	if n := len(board["jobs"].([]any)); n != 0 {
		t.Fatalf("%d unapproved postings leaked to the board", n)
	}
	h.expect(http.StatusNotFound, "GET", "/api/v1/jobs/"+strconv.FormatInt(jobID, 10), nil)

	// ---- the consultant's review ---------------------------------------

	admin := h.expect(http.StatusOK, "POST", "/api/v1/auth/login", map[string]string{
		"email": "consultant@azma-associates.com", "password": "consultant password",
	})
	adminToken := admin["token"].(string)
	h.token = adminToken

	queue := h.expect(http.StatusOK, "GET", "/api/v1/admin/jobs?status=pending", nil)
	if n := len(queue["jobs"].([]any)); n != 2 {
		t.Fatalf("review queue has %d postings, want 2", n)
	}
	if first := queue["jobs"].([]any)[0].(map[string]any); first["employerEmail"] != "hr@nippon-asset.example" {
		t.Errorf("review queue does not name the client: %v", first)
	}
	h.expect(http.StatusBadRequest, "PUT", "/api/v1/admin/jobs/"+strconv.FormatInt(jobID, 10)+"/status",
		map[string]any{"status": "rejected"}) // a rejection has to say why
	published := h.expect(http.StatusOK, "PUT", "/api/v1/admin/jobs/"+strconv.FormatInt(jobID, 10)+"/status",
		map[string]any{"status": "published"})
	if published["publishedAt"] == nil {
		t.Fatalf("published posting has no publishedAt: %v", published)
	}
	h.expect(http.StatusOK, "PUT", "/api/v1/admin/jobs/"+strconv.FormatInt(confidentialID, 10)+"/status",
		map[string]any{"status": "published"})

	// ---- the board -----------------------------------------------------

	h.token = ""
	board = h.expect(http.StatusOK, "GET", "/api/v1/jobs", nil)
	jobs := board["jobs"].([]any)
	if len(jobs) != 2 || board["total"].(float64) != 2 {
		t.Fatalf("board = %v", board)
	}
	for _, j := range jobs {
		job := j.(map[string]any)
		if job["confidential"] == true && job["company"] != confidentialLabel {
			t.Errorf("a confidential client was named on the board: %v", job["company"])
		}
		if job["reviewNote"] != nil {
			t.Errorf("an internal review note reached the board: %v", job["reviewNote"])
		}
	}
	filtered := h.expect(http.StatusOK, "GET", "/api/v1/jobs?q=japan+equities", nil)
	if n := len(filtered["jobs"].([]any)); n != 1 {
		t.Errorf("search found %d postings, want 1", n)
	}
	if n := len(h.expect(http.StatusOK, "GET", "/api/v1/jobs?sector=Private+Equity", nil)["jobs"].([]any)); n != 0 {
		t.Errorf("sector filter matched the wrong postings")
	}
	h.expect(http.StatusBadRequest, "GET", "/api/v1/jobs?sector=Nonsense", nil)
	h.expect(http.StatusOK, "GET", "/api/v1/jobs/"+strconv.FormatInt(jobID, 10), nil)

	// ---- applying ------------------------------------------------------

	h.token = candToken
	h.expect(http.StatusBadRequest, "POST", "/api/v1/candidate/applications", map[string]any{
		"jobId": confidentialID, "resumeId": resumeID + 999,
	})
	h.expect(http.StatusBadRequest, "POST", "/api/v1/candidate/applications", map[string]any{"jobId": 999999})
	app := h.expect(http.StatusCreated, "POST", "/api/v1/candidate/applications", map[string]any{
		"jobId": jobID, "resumeId": resumeID, "coverNote": "I have run a Japan equity book for ten years.",
	})
	appID := int64(app["id"].(float64))
	h.expect(http.StatusConflict, "POST", "/api/v1/candidate/applications", map[string]any{"jobId": jobID})

	h.expect(http.StatusNoContent, "PUT", "/api/v1/candidate/saved-jobs/"+strconv.FormatInt(confidentialID, 10), nil)
	h.expect(http.StatusNoContent, "PUT", "/api/v1/candidate/saved-jobs/"+strconv.FormatInt(confidentialID, 10), nil)
	me = h.expect(http.StatusOK, "GET", "/api/v1/candidate/me", nil)
	if n := len(me["savedJobs"].([]any)); n != 1 {
		t.Fatalf("saved %d positions, want 1", n)
	}
	apps := me["applications"].([]any)
	if len(apps) != 1 {
		t.Fatalf("%d applications, want 1", len(apps))
	}
	if a := apps[0].(map[string]any); a["jobTitle"] != "Portfolio Manager, Japan Equities" || a["status"] != "submitted" {
		t.Fatalf("application = %v", a)
	}

	// ---- what the client sees ------------------------------------------

	h.token = empToken
	applicants := h.expect(http.StatusOK, "GET", "/api/v1/employer/jobs/"+strconv.FormatInt(jobID, 10)+"/applications", nil)
	list := applicants["applicants"].([]any)
	if len(list) != 1 {
		t.Fatalf("%d applicants, want 1", len(list))
	}
	first := list[0].(map[string]any)
	if first["presented"] != false || first["name"] != "" || first["email"] != "" {
		t.Fatalf("the client saw an un-presented candidate's identity: %v", first)
	}
	if first["headline"] != "Equity PM, Tokyo" || first["yearsExperience"].(float64) != 12 {
		t.Fatalf("the client cannot see the professional summary: %v", first)
	}
	// Someone else's posting is not theirs to read.
	h.expect(http.StatusNotFound, "GET", "/api/v1/employer/jobs/999999/applications", nil)
	// Shortlisting is the consultant's call.
	h.expect(http.StatusBadRequest, "PUT", "/api/v1/employer/applications/"+strconv.FormatInt(appID, 10)+"/status",
		map[string]any{"status": "shortlisted"})
	h.expect(http.StatusOK, "PUT", "/api/v1/employer/applications/"+strconv.FormatInt(appID, 10)+"/status",
		map[string]any{"status": "under_review"})

	// The consultant presents the candidate, which releases their details.
	h.token = adminToken
	h.expect(http.StatusOK, "PUT", "/api/v1/admin/applications/"+strconv.FormatInt(appID, 10)+"/status",
		map[string]any{"status": "shortlisted"})
	h.token = empToken
	applicants = h.expect(http.StatusOK, "GET", "/api/v1/employer/jobs/"+strconv.FormatInt(jobID, 10)+"/applications", nil)
	first = applicants["applicants"].([]any)[0].(map[string]any)
	if first["presented"] != true || first["name"] != "Kenji Watanabe" || first["email"] != "kenji@example.com" {
		t.Fatalf("a presented candidate is still hidden from the client: %v", first)
	}
	if first["resumeDownloadUrl"] != nil {
		t.Errorf("the client was given a direct resume link: %v", first["resumeDownloadUrl"])
	}

	// The consultant works from the document itself.
	h.token = adminToken
	cands := h.expect(http.StatusOK, "GET", "/api/v1/admin/candidates", nil)
	cl := cands["candidates"].([]any)
	if len(cl) != 1 {
		t.Fatalf("%d submitted candidates, want 1", len(cl))
	}
	cs := cl[0].(map[string]any)
	if cs["email"] != "kenji@example.com" || cs["resumeCount"].(float64) != 1 {
		t.Fatalf("candidate summary = %v", cs)
	}
	if rec := h.raw("GET", dl, adminToken); rec.Code != http.StatusOK {
		t.Errorf("consultant resume download: %d", rec.Code)
	}
	detail := h.expect(http.StatusOK, "GET", "/api/v1/admin/candidates/"+cs["userId"].(string), nil)
	if n := len(detail["resumes"].([]any)); n != 1 {
		t.Errorf("candidate detail resumes = %d", n)
	}

	// ---- editing a live posting pulls it off the board -----------------

	h.token = empToken
	edited := h.expect(http.StatusOK, "PUT", "/api/v1/employer/jobs/"+strconv.FormatInt(jobID, 10), map[string]any{
		"title": "Portfolio Manager, Japan Equities (updated)", "company": "Nippon Asset Management",
		"location": "Tokyo", "sector": "Asset Management",
		"description": "Manage a long-only Japan equity book for institutional clients, reporting to the CIO.",
		"submit":      true,
	})
	if edited["status"] != "pending" || edited["publishedAt"] != nil {
		t.Fatalf("an edited posting stayed live: %v", edited)
	}
	h.token = ""
	if n := len(h.expect(http.StatusOK, "GET", "/api/v1/jobs", nil)["jobs"].([]any)); n != 1 {
		t.Error("the edited posting is still on the board")
	}

	// ---- withdrawing ---------------------------------------------------

	h.token = candToken
	w := h.expect(http.StatusOK, "POST", "/api/v1/candidate/applications/"+strconv.FormatInt(appID, 10)+"/withdraw", nil)
	if w["status"] != "withdrawn" {
		t.Fatalf("withdraw = %v", w)
	}
	h.token = empToken
	h.expect(http.StatusConflict, "PUT", "/api/v1/employer/applications/"+strconv.FormatInt(appID, 10)+"/status",
		map[string]any{"status": "offer"})

	// ---- consultation requests -----------------------------------------

	h.token = ""
	h.expect(http.StatusBadRequest, "POST", "/api/v1/inquiries", map[string]any{
		"kind": "chat", "name": "Hiro", "email": "hiro@example.com", "message": "hello",
	})
	h.expect(http.StatusBadRequest, "POST", "/api/v1/inquiries", map[string]any{
		"kind": "hiring", "name": "Hiro", "email": "not-an-email", "message": "hello",
	})
	inq := h.expect(http.StatusCreated, "POST", "/api/v1/inquiries", map[string]any{
		"kind": "hiring", "name": "Hiro Sato", "email": "hiro@example.com", "company": "Sato Capital",
		"office": "tokyo", "message": "We are building out a Tokyo PE team and would like to discuss a search.",
	})
	inqID := int64(inq["id"].(float64))
	if inq["status"] != "new" {
		t.Fatalf("inquiry = %v", inq)
	}

	// A signed-in sender's message is linked to their account.
	h.token = candToken
	h.expect(http.StatusCreated, "POST", "/api/v1/inquiries", map[string]any{
		"kind": "career", "name": "Kenji Watanabe", "email": "kenji@example.com",
		"message": "I would like to discuss moving into a PM seat.",
	})
	if mine := h.expectArray(http.StatusOK, "GET", "/api/v1/my/inquiries"); len(mine) != 1 {
		t.Fatalf("the candidate sees %d of their own messages, want 1", len(mine))
	}

	h.token = adminToken
	box := h.expect(http.StatusOK, "GET", "/api/v1/admin/inquiries?status=new", nil)
	if n := len(box["inquiries"].([]any)); n != 2 {
		t.Fatalf("%d new inquiries, want 2", n)
	}
	h.expect(http.StatusBadRequest, "PUT", "/api/v1/admin/inquiries/"+strconv.FormatInt(inqID, 10)+"/status",
		map[string]any{"status": "pending"})
	handled := h.expect(http.StatusOK, "PUT", "/api/v1/admin/inquiries/"+strconv.FormatInt(inqID, 10)+"/status",
		map[string]any{"status": "in_progress"})
	if handled["handledAt"] == nil {
		t.Fatalf("handled inquiry = %v", handled)
	}

	// The CMS Users screen still lists administrators only.
	users := h.expectArray(http.StatusOK, "GET", "/api/v1/admin/users")
	if len(users) != 1 {
		t.Fatalf("admin user list has %d entries, want 1 (app accounts are not CMS users)", len(users))
	}
}

// raw issues a request with an explicit token (including none) and hands back
// the recorder, for responses that are not JSON objects.
func (h *harness) raw(method, path, token string) *httptest.ResponseRecorder {
	h.t.Helper()
	req := httptest.NewRequest(method, path, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	h.h.ServeHTTP(rec, req)
	return rec
}

// expectArray is expect() for endpoints that answer with a JSON array.
func (h *harness) expectArray(want int, method, path string) []any {
	h.t.Helper()
	rec := h.raw(method, path, h.token)
	if rec.Code != want {
		h.t.Fatalf("%s %s: status %d, want %d: %s", method, path, rec.Code, want, rec.Body)
	}
	var arr []any
	if err := json.Unmarshal(rec.Body.Bytes(), &arr); err != nil {
		h.t.Fatalf("%s %s: %v: %s", method, path, err, rec.Body)
	}
	return arr
}

func uploadResume(t *testing.T, h *harness, name string, data []byte) (int, map[string]any) {
	t.Helper()
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	fw, _ := w.CreateFormFile("file", name)
	_, _ = fw.Write(data)
	_ = w.Close()
	req := httptest.NewRequest("POST", "/api/v1/candidate/resumes", &buf)
	req.Header.Set("Content-Type", w.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+h.token)
	rec := httptest.NewRecorder()
	h.h.ServeHTTP(rec, req)
	var obj map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &obj)
	return rec.Code, obj
}
