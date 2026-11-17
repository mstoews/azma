package api

import (
	"encoding/json"
	"html"
	"os"
	"strings"
	"testing"
)

func TestSanitizeContentRemovesActiveContent(t *testing.T) {
	cases := map[string]string{
		`<p>hi</p><script>alert(1)</script>`:                  "<script",
		`<img src="/x.jpg" onerror="alert(1)">`:               "onerror",
		`<a href="javascript:alert(1)">x</a>`:                 "javascript:",
		`<a href="JaVaScRiPt:alert(1)">x</a>`:                 "alert",
		`<img src="data:image/svg+xml;base64,PHN2Zz4=">`:      "data:",
		`<iframe src="https://evil.example"></iframe>`:        "<iframe",
		`<p style="background:url(javascript:alert(1))">x`:    "style",
		`<svg><script>alert(1)</script></svg>`:                "alert",
		`<form action="/api/v1/admin"><input></form>`:         "<form",
		`<p class="x" onclick="alert(1)">x</p>`:               "onclick",
		`<a href="/x" target="_top">x</a>`:                    "_top",
		`<p class="a&quot; onmouseover=&quot;alert(1)">x</p>`: "onmouseover",
	}
	for in, banned := range cases {
		if out := SanitizeContent(in); strings.Contains(strings.ToLower(out), strings.ToLower(banned)) {
			t.Errorf("SanitizeContent(%q) = %q, still contains %q", in, out, banned)
		}
	}
}

func TestSanitizeContentKeepsEditorAndWordPressMarkup(t *testing.T) {
	keep := []string{
		`<h2>Title</h2><p>Text with <strong>bold</strong>, <em>italic</em> and<br/>a break.</p>`,
		`<ul><li>one</li></ul><ol><li>two</li></ol>`,
		`<p><a href="mailto:company@azma-associates.com">company@azma-associates.com</a></p>`,
		`<p><a href="/contact">Contact</a> <a href="tel:+81312345678">Call</a></p>`,
		`<figure class="wp-block-image size-large"><img src="/media/2026/11/a.jpg" alt="Office" width="1200" height="800"/></figure>`,
		`<div class="wp-block-buttons is-layout-flex wp-block-buttons-is-layout-flex"><p>x</p></div>`,
		`<table><thead><tr><th scope="col">A</th></tr></thead><tbody><tr><td colspan="2">B</td></tr></tbody></table>`,
	}
	for _, in := range keep {
		if out := SanitizeContent(in); out != in {
			t.Errorf("SanitizeContent changed safe markup\n in: %s\nout: %s", in, out)
		}
	}
}

func TestSanitizeContentExternalBlankLinksGetNoopener(t *testing.T) {
	out := SanitizeContent(`<a href="https://example.com" target="_blank">x</a>`)
	if !strings.Contains(out, `target="_blank"`) || !strings.Contains(out, "noopener") {
		t.Errorf("got %q, want target=_blank kept with rel noopener", out)
	}
	if strings.Contains(out, "nofollow") {
		t.Errorf("got %q, want no nofollow", out)
	}
}

// The content the site was seeded from must come through intact; only entity
// spelling may change (&nbsp; becomes a literal U+00A0, and so on).
func TestSanitizeContentKeepsSeededContent(t *testing.T) {
	b, err := os.ReadFile("../../src/app/data/site-data.json")
	if err != nil {
		t.Skip("bundled site data not found:", err)
	}
	var d struct {
		Pages, Posts []struct{ Title, Content string }
	}
	if err := json.Unmarshal(b, &d); err != nil {
		t.Fatal(err)
	}
	for _, p := range append(d.Pages, d.Posts...) {
		if html.UnescapeString(SanitizeContent(p.Content)) != html.UnescapeString(p.Content) {
			t.Errorf("sanitizing changed the content of %q", p.Title)
		}
	}
}
