// Command server runs the CMS API (and, with STATIC_DIR set, the site).
package main

import (
	"context"
	"os"
	"time"

	"github.com/mstoews/azma-associates/server/api"
	"github.com/mstoews/azma-associates/server/db/dbutil"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	"github.com/mstoews/azma-associates/server/storage"
	"github.com/mstoews/azma-associates/server/util"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

func main() {
	config, err := util.LoadConfig(".")
	if err != nil {
		log.Fatal().Err(err).Msg("cannot load config")
	}
	if !config.IsProduction() {
		log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr, TimeFormat: time.Kitchen})
	}

	if config.AutoMigrate {
		if err := dbutil.MigrateUp(config.DBSource); err != nil {
			log.Fatal().Err(err).Msg("migrations failed")
		}
		log.Info().Msg("schema up to date")
	}

	ctx := context.Background()
	pool, err := dbutil.Connect(ctx, config.DBSource)
	if err != nil {
		log.Fatal().Err(err).Msg("cannot connect to db")
	}
	defer pool.Close()
	store := db.NewStore(pool)

	// Housekeeping: prune long-expired sessions once a day.
	go func() {
		for {
			if err := store.DeleteExpiredSessions(ctx); err != nil {
				log.Warn().Err(err).Msg("session cleanup failed")
			}
			time.Sleep(24 * time.Hour)
		}
	}()

	var media storage.Store
	if config.MediaBucket != "" {
		media, err = storage.NewGCS(ctx, config.MediaBucket, config.MediaBucketPrefix)
	} else {
		media, err = storage.NewLocal(config.MediaDir)
	}
	if err != nil {
		log.Fatal().Err(err).Msg("cannot open media store")
	}
	log.Info().Str("media", media.Describe()).Msg("media store ready")

	server := api.NewServer(config, store, media)
	log.Info().Str("addr", config.HTTPServerAddress).Str("static", config.StaticDir).Msg("listening")
	if err := server.Start(); err != nil {
		log.Fatal().Err(err).Msg("server stopped")
	}
}
