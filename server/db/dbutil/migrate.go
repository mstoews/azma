// Package dbutil applies the embedded schema migrations.
package dbutil

import (
	"errors"
	"fmt"
	"net/url"
	"strings"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	"github.com/mstoews/azma-associates/server/db/migration"
)

// newMigrate builds a migrator over the embedded SQL files. golang-migrate's
// pgx/v5 driver registers under the "pgx5" scheme, so postgres:// and
// postgresql:// DSNs are rewritten to it.
func newMigrate(dsn string) (*migrate.Migrate, error) {
	dsn = DirectDSN(dsn)
	src, err := iofs.New(migration.FS, ".")
	if err != nil {
		return nil, err
	}
	for _, p := range []string{"postgresql://", "postgres://"} {
		if strings.HasPrefix(dsn, p) {
			dsn = "pgx5://" + strings.TrimPrefix(dsn, p)
			break
		}
	}
	return migrate.NewWithSourceInstance("iofs", src, dsn)
}

// MigrateUp applies every pending migration. No pending migrations is not an error.
func MigrateUp(dsn string) error {
	m, err := newMigrate(dsn)
	if err != nil {
		return fmt.Errorf("init migrations: %w", err)
	}
	defer m.Close()
	if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return fmt.Errorf("migrate up: %w", err)
	}
	return nil
}

// MigrateDown rolls back n migrations (n <= 0 rolls back all of them).
func MigrateDown(dsn string, n int) error {
	m, err := newMigrate(dsn)
	if err != nil {
		return fmt.Errorf("init migrations: %w", err)
	}
	defer m.Close()
	if n <= 0 {
		err = m.Down()
	} else {
		err = m.Steps(-n)
	}
	if err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return fmt.Errorf("migrate down: %w", err)
	}
	return nil
}

// Version reports the current schema version and whether it is dirty.
func Version(dsn string) (uint, bool, error) {
	m, err := newMigrate(dsn)
	if err != nil {
		return 0, false, err
	}
	defer m.Close()
	v, dirty, err := m.Version()
	if errors.Is(err, migrate.ErrNilVersion) {
		return 0, false, nil
	}
	return v, dirty, err
}

// DirectDSN rewrites a Neon pooled endpoint (ep-x-pooler.region.aws.neon.tech)
// to its direct endpoint. Migrations hold a session-level advisory lock, which
// a transaction-mode pooler can drop between statements. Other DSNs are
// returned unchanged.
func DirectDSN(dsn string) string {
	u, err := url.Parse(dsn)
	if err != nil || !strings.HasSuffix(u.Hostname(), ".neon.tech") {
		return dsn
	}
	host := u.Hostname()
	first, rest, ok := strings.Cut(host, ".")
	if !ok || !strings.HasSuffix(first, "-pooler") {
		return dsn
	}
	direct := strings.TrimSuffix(first, "-pooler") + "." + rest
	if port := u.Port(); port != "" {
		u.Host = direct + ":" + port
	} else {
		u.Host = direct
	}
	return u.String()
}
