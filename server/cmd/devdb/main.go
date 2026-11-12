// Command devdb runs a throwaway local PostgreSQL for development on machines
// without Docker. It downloads the PostgreSQL binaries on first run, keeps
// data in ./.devdb, and stops on Ctrl-C.
//
//	go run ./cmd/devdb
//	DB_SOURCE=postgresql://cms:cms@localhost:55440/cms?sslmode=disable
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	embeddedpostgres "github.com/fergusstrange/embedded-postgres"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

func main() {
	port := flag.Uint("port", 55440, "port to listen on")
	dir := flag.String("dir", ".devdb", "data directory")
	flag.Parse()

	abs, err := filepath.Abs(*dir)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	pg := embeddedpostgres.NewDatabase(embeddedpostgres.DefaultConfig().
		Version(embeddedpostgres.V16).
		Port(uint32(*port)).
		Username("cms").Password("cms").Database("cms").
		RuntimePath(filepath.Join(abs, "runtime")).
		DataPath(filepath.Join(abs, "data")).
		BinariesPath(filepath.Join(abs, "bin")).
		CachePath(filepath.Join(abs, "cache")))
	if err := pg.Start(); err != nil {
		fmt.Fprintln(os.Stderr, "start postgres:", err)
		os.Exit(1)
	}
	// A second database for `go test` (TEST_DB_SOURCE), which drops and
	// recreates its schema on every run.
	dsn := fmt.Sprintf("postgresql://cms:cms@localhost:%d/cms?sslmode=disable", *port)
	if conn, err := pgx.Connect(context.Background(), dsn); err == nil {
		_, err = conn.Exec(context.Background(), "CREATE DATABASE cms_test")
		var pgErr *pgconn.PgError
		if err != nil && !(errors.As(err, &pgErr) && pgErr.Code == "42P04") {
			fmt.Fprintln(os.Stderr, "create cms_test:", err)
		}
		conn.Close(context.Background())
	}
	fmt.Printf("postgres ready\nDB_SOURCE=%s\nTEST_DB_SOURCE=postgresql://cms:cms@localhost:%d/cms_test?sslmode=disable\n", dsn, *port)

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	<-sig
	if err := pg.Stop(); err != nil {
		fmt.Fprintln(os.Stderr, "stop postgres:", err)
		os.Exit(1)
	}
}
