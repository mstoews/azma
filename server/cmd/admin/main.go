// Command admin manages administrator accounts and the schema from the shell.
// It is how the first administrator is created.
//
//	go run ./cmd/admin create -email you@example.com -name "Your Name"
//	go run ./cmd/admin reset-password -email you@example.com
//	go run ./cmd/admin list
//	go run ./cmd/admin migrate [up|down|version]
//	go run ./cmd/admin sanitize-content [-dry-run]
//
// Passwords are read from the terminal without echo, or from the
// ADMIN_PASSWORD environment variable for scripted use.
package main

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/mstoews/azma-associates/server/api"
	"github.com/mstoews/azma-associates/server/db/dbutil"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	"github.com/mstoews/azma-associates/server/util"
	"golang.org/x/term"
)

func usage() {
	fmt.Fprintln(os.Stderr, "usage: admin <create|reset-password|enable|disable|list|migrate|sanitize-content> [flags]")
	os.Exit(2)
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	cmd, args := os.Args[1], os.Args[2:]
	config, err := util.LoadConfig(".")
	fatal(err)

	if cmd == "migrate" {
		runMigrate(config, args)
		return
	}

	ctx := context.Background()
	pool, err := dbutil.Connect(ctx, config.DBSource)
	fatal(err)
	defer pool.Close()
	store := db.NewStore(pool)

	fs := flag.NewFlagSet(cmd, flag.ExitOnError)
	email := fs.String("email", "", "administrator email")
	name := fs.String("name", "", "display name")
	dryRun := fs.Bool("dry-run", false, "sanitize-content: report what would change without writing")
	_ = fs.Parse(args)

	switch cmd {
	case "create":
		need(*email)
		hash, err := api.HashPassword(readPassword())
		fatal(err)
		u, err := store.CreateUser(ctx, db.CreateUserParams{Email: *email, Name: *name, PasswordHash: hash, Role: "admin"})
		fatal(err)
		fmt.Printf("created administrator %s (%s)\n", u.Email, u.ID)
	case "reset-password":
		need(*email)
		u := mustUser(ctx, store, *email)
		hash, err := api.HashPassword(readPassword())
		fatal(err)
		fatal(store.SetUserPassword(ctx, db.SetUserPasswordParams{ID: u.ID, PasswordHash: hash}))
		fatal(store.RevokeUserSessions(ctx, u.ID))
		fmt.Printf("password reset for %s; existing sessions signed out\n", u.Email)
	case "enable", "disable":
		need(*email)
		u := mustUser(ctx, store, *email)
		_, err := store.UpdateUser(ctx, db.UpdateUserParams{ID: u.ID, Name: u.Name, Disabled: cmd == "disable"})
		fatal(err)
		if cmd == "disable" {
			fatal(store.RevokeUserSessions(ctx, u.ID))
		}
		fmt.Printf("%sd %s\n", cmd, u.Email)
	case "list":
		users, err := store.ListUsers(ctx)
		fatal(err)
		for _, u := range users {
			state := "active"
			if u.Disabled {
				state = "disabled"
			}
			fmt.Printf("%-36s  %-30s  %-20s  %s\n", u.ID, u.Email, u.Name, state)
		}
	case "sanitize-content":
		fatal(sanitizeContent(ctx, store, *dryRun))
	default:
		usage()
	}
}

func runMigrate(config util.Config, args []string) {
	action := "up"
	if len(args) > 0 {
		action = args[0]
	}
	switch action {
	case "up":
		fatal(dbutil.MigrateUp(config.DBSource))
	case "down":
		fatal(dbutil.MigrateDown(config.DBSource, 1))
	case "version":
	default:
		usage()
	}
	v, dirty, err := dbutil.Version(config.DBSource)
	fatal(err)
	fmt.Printf("schema version %d (dirty=%v)\n", v, dirty)
}

func mustUser(ctx context.Context, store db.Store, email string) db.User {
	u, err := store.GetUserByEmail(ctx, email)
	if errors.Is(err, pgx.ErrNoRows) {
		fatal(fmt.Errorf("no user with email %s", email))
	}
	fatal(err)
	return u
}

func readPassword() string {
	if pw := os.Getenv("ADMIN_PASSWORD"); pw != "" {
		return pw
	}
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
		return strings.TrimRight(line, "\r\n")
	}
	fmt.Fprintf(os.Stderr, "Password (min %d chars): ", api.MinPasswordLength)
	a, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Fprintln(os.Stderr)
	fatal(err)
	fmt.Fprint(os.Stderr, "Confirm password: ")
	b, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Fprintln(os.Stderr)
	fatal(err)
	if string(a) != string(b) {
		fatal(errors.New("passwords do not match"))
	}
	return string(a)
}

func need(v string) {
	if v == "" {
		fatal(errors.New("-email is required"))
	}
}

func fatal(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

// sanitizeContent runs every stored page, profile and translation body through
// api.SanitizeContent, the same allowlist the API now applies on save, so HTML
// saved before that check existed cannot reach the public site. It is
// idempotent: rows that are already clean are left untouched.
func sanitizeContent(ctx context.Context, store db.Store, dryRun bool) error {
	changed := 0
	check := func(what, content string, write func(string) error) error {
		clean := api.SanitizeContent(content)
		if clean == content {
			return nil
		}
		changed++
		fmt.Printf("%-40s %6d -> %6d bytes\n", what, len(content), len(clean))
		if dryRun {
			return nil
		}
		return write(clean)
	}

	pages, err := store.ListPages(ctx)
	if err != nil {
		return err
	}
	for _, p := range pages {
		if err := check("page "+p.Slug, p.Content, func(c string) error {
			return store.SetPageContent(ctx, db.SetPageContentParams{ID: p.ID, Content: c})
		}); err != nil {
			return err
		}
	}
	profiles, err := store.ListProfiles(ctx)
	if err != nil {
		return err
	}
	for _, p := range profiles {
		if err := check("profile "+p.Slug, p.Content, func(c string) error {
			return store.SetProfileContent(ctx, db.SetProfileContentParams{ID: p.ID, Content: c})
		}); err != nil {
			return err
		}
	}
	pageTr, err := store.ListPageTranslations(ctx)
	if err != nil {
		return err
	}
	for _, t := range pageTr {
		what := fmt.Sprintf("page #%d [%s]", t.PageID, t.Locale)
		if err := check(what, t.Content, func(c string) error {
			return store.SetPageTranslationContent(ctx, db.SetPageTranslationContentParams{PageID: t.PageID, Locale: t.Locale, Content: c})
		}); err != nil {
			return err
		}
	}
	profileTr, err := store.ListProfileTranslations(ctx)
	if err != nil {
		return err
	}
	for _, t := range profileTr {
		what := fmt.Sprintf("profile #%d [%s]", t.ProfileID, t.Locale)
		if err := check(what, t.Content, func(c string) error {
			return store.SetProfileTranslationContent(ctx, db.SetProfileTranslationContentParams{ProfileID: t.ProfileID, Locale: t.Locale, Content: c})
		}); err != nil {
			return err
		}
	}

	verb := "sanitized"
	if dryRun {
		verb = "would sanitize"
	}
	fmt.Printf("%s %d of %d bodies\n", verb, changed, len(pages)+len(profiles)+len(pageTr)+len(profileTr))
	return nil
}
