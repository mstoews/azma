package dbutil

import (
	"fmt"
	"io/fs"
	"testing"

	"github.com/mstoews/azma-associates/server/db/migration"
)

func TestDirectDSN(t *testing.T) {
	cases := map[string]string{
		"postgresql://u:p@ep-cool-1-pooler.ap-southeast-1.aws.neon.tech/neondb?sslmode=require": "postgresql://u:p@ep-cool-1.ap-southeast-1.aws.neon.tech/neondb?sslmode=require",
		"postgresql://u:p@ep-cool-1.ap-southeast-1.aws.neon.tech/neondb?sslmode=require":        "postgresql://u:p@ep-cool-1.ap-southeast-1.aws.neon.tech/neondb?sslmode=require",
		"postgresql://cms:cms@localhost:55440/cms?sslmode=disable":                              "postgresql://cms:cms@localhost:55440/cms?sslmode=disable",
	}
	for in, want := range cases {
		if got := DirectDSN(in); got != want {
			t.Errorf("DirectDSN(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestLatestVersionMatchesEmbeddedMigrations(t *testing.T) {
	got, err := LatestVersion()
	if err != nil {
		t.Fatal(err)
	}
	if got < 3 { // 000003_content_translations exists
		t.Fatalf("LatestVersion() = %d, want at least 3", got)
	}
	ups, _ := fs.Glob(migration.FS, fmt.Sprintf("%06d_*.up.sql", got))
	if len(ups) != 1 {
		t.Errorf("LatestVersion() = %d, but there is no %06d_*.up.sql migration", got, got)
	}
	newer, _ := fs.Glob(migration.FS, fmt.Sprintf("%06d_*.up.sql", got+1))
	if len(newer) != 0 {
		t.Errorf("LatestVersion() = %d, but %v exists", got, newer)
	}
}
