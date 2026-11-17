package api

import (
	"regexp"

	"github.com/microcosm-cc/bluemonday"
)

// contentPolicy is the allowlist for CMS page and profile HTML. The public
// site renders that HTML without Angular's sanitizer (so theme classes
// survive), so this is the only thing standing between an admin session and
// script on the public site. Everything not listed here is removed: scripts,
// iframes, forms, event handlers, inline styles, and javascript:/data: URLs.
//
// It covers what the content editor produces (headings, lists, links, images
// in figures) and what the WordPress import contains (wp-block-* classes).
var contentPolicy = newContentPolicy()

var (
	classNames  = regexp.MustCompile(`^[A-Za-z0-9_\- ]*$`)
	blankTarget = regexp.MustCompile(`^_blank$`)
	dimension   = regexp.MustCompile(`^[0-9]{1,5}$`)
	loading     = regexp.MustCompile(`^(lazy|eager)$`)
	decoding    = regexp.MustCompile(`^(async|sync|auto)$`)
	cellScope   = regexp.MustCompile(`^(row|col|rowgroup|colgroup)$`)
)

func newContentPolicy() *bluemonday.Policy {
	p := bluemonday.NewPolicy()

	p.AllowElements(
		"p", "br", "hr", "div", "span",
		"h2", "h3", "h4", "h5", "h6",
		"strong", "b", "em", "i", "u", "s", "small", "sub", "sup", "mark",
		"blockquote", "code", "pre",
		"ul", "ol", "li", "dl", "dt", "dd",
		"figure", "figcaption",
		"table", "caption", "thead", "tbody", "tfoot", "tr", "th", "td",
	)
	p.AllowAttrs("class").Matching(classNames).Globally()
	p.AllowAttrs("lang", "dir").Globally()

	// Links: site paths, http(s), mailto and tel only.
	// (Not AllowStandardURLs: it also forces rel="nofollow" onto every link.)
	p.RequireParseableURLs(true)
	p.AllowURLSchemes("http", "https", "mailto", "tel")
	p.AllowRelativeURLs(true)
	p.AllowAttrs("href", "title").OnElements("a")
	p.AllowAttrs("target").Matching(blankTarget).OnElements("a")
	// External links get rel="noreferrer" (and "noopener" with target=_blank),
	// so an opened site can neither see the referring page nor script it.
	// Own-site links are left alone, and nothing gets nofollow.
	p.RequireNoReferrerOnFullyQualifiedLinks(true)

	// Images (inserted from the media library as <img src alt width height>).
	p.AllowAttrs("src", "alt", "title").OnElements("img")
	p.AllowAttrs("width", "height").Matching(dimension).OnElements("img")
	p.AllowAttrs("loading").Matching(loading).OnElements("img")
	p.AllowAttrs("decoding").Matching(decoding).OnElements("img")

	p.AllowAttrs("colspan", "rowspan").Matching(dimension).OnElements("td", "th")
	p.AllowAttrs("scope").Matching(cellScope).OnElements("th")
	return p
}

// SanitizeContent returns html with everything outside contentPolicy removed.
func SanitizeContent(html string) string {
	return contentPolicy.Sanitize(html)
}
