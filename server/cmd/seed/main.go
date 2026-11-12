// Command seed imports the content of the static site (the JSON the Angular
// app was built from, plus the WordPress uploads folder) into the database.
//
//	go run ./cmd/seed                     # from server/, with the defaults below
//	go run ./cmd/seed -overwrite          # replace pages/profiles already imported
//
// It is idempotent: pages and profiles are matched on their WordPress ID, the
// menu is only created when empty, settings only when unset, and media rows
// are keyed on URL.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io/fs"
	"mime"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/mstoews/azma-associates/server/api"
	"github.com/mstoews/azma-associates/server/db/dbutil"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	"github.com/mstoews/azma-associates/server/util"
	_ "golang.org/x/image/webp"
)

type siteData struct {
	Posts []struct {
		ID      int32    `json:"id"`
		Title   string   `json:"title"`
		Excerpt []string `json:"excerpt"`
		Thumb   string   `json:"thumb"`
		Hero    string   `json:"hero"`
		Content string   `json:"content"`
	} `json:"posts"`
	Pages []struct {
		ID      int32  `json:"id"`
		Title   string `json:"title"`
		Hero    string `json:"hero"`
		Content string `json:"content"`
	} `json:"pages"`
}

// Values that were constants in src/app/site-data.ts.
var defaultSettings = db.UpdateSettingsParams{
	SiteName:        "AZMA & Associates",
	Tagline:         "We are an APAC professional recruitment firm.",
	HomeDescription: "We are an Asia Pacific professional search firm.",
	HomeHeaderImage: "/wp-content/uploads/2021/07/cropped-cropped-max-bender-VmX3vmBecFE-unsplash-scaled-1.jpg",
	Logo:            "/wp-content/uploads/2021/07/logo-3.png",
}

// WordPress writes resized copies as name-768x860.jpg; only originals are
// listed in the media library (the copies still exist and still serve).
var wpVariant = regexp.MustCompile(`-\d+x\d+\.[A-Za-z0-9]+$`)

func main() {
	dataPath := flag.String("data", "../src/app/data/site-data.json", "site-data.json exported from WordPress")
	uploads := flag.String("uploads", "../public/wp-content/uploads", "WordPress uploads folder (empty to skip)")
	overwrite := flag.Bool("overwrite", false, "overwrite pages/profiles that were already imported")
	flag.Parse()

	config, err := util.LoadConfig(".")
	fatal(err)
	if config.AutoMigrate {
		fatal(dbutil.MigrateUp(config.DBSource))
	}
	ctx := context.Background()
	pool, err := dbutil.Connect(ctx, config.DBSource)
	fatal(err)
	defer pool.Close()
	store := db.NewStore(pool)

	raw, err := os.ReadFile(*dataPath)
	fatal(err)
	var data siteData
	fatal(json.Unmarshal(raw, &data))

	err = store.ExecTx(ctx, func(q db.Querier) error {
		st, err := q.GetSettings(ctx)
		if err != nil {
			return err
		}
		if st.SiteName == "" {
			if _, err := q.UpdateSettings(ctx, defaultSettings); err != nil {
				return err
			}
			fmt.Println("settings: imported")
		}

		pageIDs := make([]int64, 0, len(data.Pages))
		for i, p := range data.Pages {
			legacy := pgtype.Int4{Int32: p.ID, Valid: true}
			existing, err := q.GetPageByLegacyID(ctx, legacy)
			switch {
			case err == nil && !*overwrite:
				pageIDs = append(pageIDs, existing.ID)
				fmt.Printf("page %-20q exists, skipped\n", p.Title)
				continue
			case err == nil:
				_, err = q.UpdatePage(ctx, db.UpdatePageParams{ID: existing.ID, Slug: existing.Slug, Title: p.Title,
					Hero: p.Hero, Content: p.Content, Published: true, SortOrder: int32((i + 1) * 10)})
				if err != nil {
					return err
				}
				pageIDs = append(pageIDs, existing.ID)
				fmt.Printf("page %-20q overwritten\n", p.Title)
			case errors.Is(err, pgx.ErrNoRows):
				row, err := q.CreatePage(ctx, db.CreatePageParams{Slug: api.Slugify(p.Title), Title: p.Title,
					Hero: p.Hero, Content: p.Content, Published: true, SortOrder: int32((i + 1) * 10), LegacyWpID: legacy})
				if err != nil {
					return fmt.Errorf("page %q: %w", p.Title, err)
				}
				pageIDs = append(pageIDs, row.ID)
				fmt.Printf("page %-20q imported as /%s\n", p.Title, row.Slug)
			default:
				return err
			}
		}

		for i, p := range data.Posts {
			legacy := pgtype.Int4{Int32: p.ID, Valid: true}
			existing, err := q.GetProfileByLegacyID(ctx, legacy)
			switch {
			case err == nil && !*overwrite:
				fmt.Printf("profile %-20q exists, skipped\n", p.Title)
			case err == nil:
				_, err = q.UpdateProfile(ctx, db.UpdateProfileParams{ID: existing.ID, Slug: existing.Slug, Title: p.Title,
					Excerpt: p.Excerpt, Thumb: p.Thumb, Hero: p.Hero, Content: p.Content, Published: true,
					SortOrder: int32((i + 1) * 10)})
				if err != nil {
					return err
				}
				fmt.Printf("profile %-20q overwritten\n", p.Title)
			case errors.Is(err, pgx.ErrNoRows):
				row, err := q.CreateProfile(ctx, db.CreateProfileParams{Slug: api.Slugify(p.Title), Title: p.Title,
					Excerpt: p.Excerpt, Thumb: p.Thumb, Hero: p.Hero, Content: p.Content, Published: true,
					SortOrder: int32((i + 1) * 10), LegacyWpID: legacy})
				if err != nil {
					return fmt.Errorf("profile %q: %w", p.Title, err)
				}
				fmt.Printf("profile %-20q imported as /profile/%s\n", p.Title, row.Slug)
			default:
				return err
			}
		}

		n, err := q.CountNavItems(ctx)
		if err != nil {
			return err
		}
		if n == 0 {
			order := int32(10)
			for i, id := range pageIDs {
				if _, err := q.CreateNavItem(ctx, db.CreateNavItemParams{Label: data.Pages[i].Title,
					PageID: pgtype.Int8{Int64: id, Valid: true}, SortOrder: order}); err != nil {
					return err
				}
				order += 10
			}
			if _, err := q.CreateNavItem(ctx, db.CreateNavItemParams{Label: "日本語",
				Href: pgtype.Text{String: "https://azma-associates.jp/", Valid: true}, SortOrder: order}); err != nil {
				return err
			}
			fmt.Printf("menu: %d items created\n", len(pageIDs)+1)
		}
		return nil
	})
	fatal(err)

	if *uploads != "" {
		fatal(importUploads(ctx, store, *uploads))
	}
	fmt.Println("seed complete")
}

// importUploads registers the WordPress uploads in the media library. The
// files themselves stay where they are: they are part of the Angular build
// and served from /wp-content/uploads.
func importUploads(ctx context.Context, store db.Store, root string) error {
	root = filepath.Clean(root)
	added := 0
	err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || strings.HasPrefix(d.Name(), ".") || wpVariant.MatchString(d.Name()) {
			return err
		}
		rel, err := filepath.Rel(root, p)
		if err != nil {
			return err
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		mt := mime.TypeByExtension(strings.ToLower(filepath.Ext(p)))
		if i := strings.IndexByte(mt, ';'); i >= 0 {
			mt = mt[:i]
		}
		var w, h pgtype.Int4
		if f, err := os.Open(p); err == nil {
			if cfg, _, err := image.DecodeConfig(f); err == nil {
				w = pgtype.Int4{Int32: int32(cfg.Width), Valid: true}
				h = pgtype.Int4{Int32: int32(cfg.Height), Valid: true}
			}
			f.Close()
		}
		_, err = store.CreateMedia(ctx, db.CreateMediaParams{
			Url: "/wp-content/uploads/" + filepath.ToSlash(rel), Filename: d.Name(),
			MimeType: mt, SizeBytes: info.Size(), Width: w, Height: h, Source: "wordpress",
		})
		if errors.Is(err, pgx.ErrNoRows) { // ON CONFLICT DO NOTHING: already registered
			return nil
		}
		if err == nil {
			added++
		}
		return err
	})
	fmt.Printf("media: %d WordPress files registered\n", added)
	return err
}

func fatal(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}
