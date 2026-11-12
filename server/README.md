# AZMA CMS server

Go API that stores the AZMA & Associates site content in PostgreSQL and lets
administrators edit it. The Angular app in the repo root reads published
content from `GET /api/v1/site` and has the admin UI at `/admin`.

Stack, following `noble-go-server`: Gin, pgx/v5, sqlc, golang-migrate,
viper (`app.env`) and zerolog. Sessions are opaque bearer tokens, and only
their SHA-256 hash is stored. Passwords are hashed with bcrypt.

## Layout

```
cmd/server   API (and, optionally, the built site)
cmd/admin    create/reset/disable administrators; run migrations
cmd/seed     import the original WordPress content into the database
cmd/devdb    local PostgreSQL without Docker (embedded-postgres)
api/         HTTP handlers           middleware/  session auth, admin gate
db/migration schema (embedded in the binary)
db/query     SQL → `sqlc generate` → db/sqlc
```

## Local development

```sh
cd server
cp app.env.example app.env        # set DB_SOURCE (Neon, or the devdb DSN)
make devdb                         # terminal 1, only if not using Neon
make seed                          # import pages, profiles, menu, settings, media
make admin EMAIL=you@example.com NAME="Your Name"   # prompts for a password
make run                           # terminal 2: API on :8080
cd .. && npm start                 # terminal 3: site on :4200, proxies /api and /media
```

Then open http://localhost:4200/admin.

For tests, `make devdb` also creates a `cms_test` database:

```sh
TEST_DB_SOURCE=postgresql://cms:cms@localhost:55440/cms_test?sslmode=disable go test ./...
```

Without `TEST_DB_SOURCE` only the unit tests run. The integration test
drops and recreates the schema, so never point it at a real database.

## Using Neon

Set `DB_SOURCE` to the Neon connection string with `sslmode=require`. Use
either the direct or the pooled endpoint: nothing here relies on
session-level state. Migrations run on startup while `AUTO_MIGRATE=true`, or
run them yourself with `go run ./cmd/admin migrate up`.

## API

| Method | Path | Who |
|---|---|---|
| GET | `/api/v1/site` | public; published content only |
| POST | `/api/v1/auth/login` | public; locks the account after `LOGIN_LOCKOUT_THRESHOLD` failures |
| GET/POST/PUT | `/api/v1/auth/me`, `/logout`, `/password` | signed in |
| CRUD | `/api/v1/admin/pages`, `/profiles` (+ `PUT …/order`) | admin |
| GET/PUT | `/api/v1/admin/nav`, `/settings` | admin |
| GET/POST/PATCH/DELETE | `/api/v1/admin/media` | admin |
| CRUD | `/api/v1/admin/users` (+ `PUT …/:id/password`) | admin |
| GET | `/api/v1/admin/audit` | admin |

Every admin write goes into `audit_log` with before/after snapshots.

## Deploying (Google Cloud project `web-azma`)

Live at https://azma-cms-555559211982.asia-northeast1.run.app (Cloud Run,
`asia-northeast1`). Health check: `/api/v1/health`. Cloud Run reserves paths
ending in `z`, so `/healthz` only works locally.

| Piece | Name |
|---|---|
| Cloud Run service | `azma-cms` (min 0 / max 3 instances) |
| Image | `asia-northeast1-docker.pkg.dev/web-azma/azma/cms` |
| Uploads | `gs://web-azma-media/media/` (private; served through `/media/...`) |
| Database | Neon, DSN in Secret Manager `azma-db-source` |
| Runtime identity | `azma-cms-run@web-azma.iam.gserviceaccount.com` (bucket objects + that secret only) |

Release, from the repo root:

```sh
gcloud builds submit --config server/cloudbuild.yaml --project web-azma --region asia-northeast1 .
server/deploy.sh                 # deploys :latest
server/deploy.sh <build-id>      # roll back to an earlier build
```

Schema migrations run when the server starts. Against Neon they go to the
direct endpoint, not the pooler (see `dbutil.DirectDSN`).

Commands against production, with the DSN taken from the secret so it never
lands in a file:

```sh
export DB_SOURCE="$(gcloud secrets versions access latest --secret azma-db-source --project web-azma)"
go run ./cmd/admin create -email you@example.com -name "Your Name"
go run ./cmd/admin list
```

Moving uploads between disk and the bucket (neither direction deletes):

```sh
./media-sync.sh upload   [dir]   # ./media → bucket
./media-sync.sh download [dir]   # bucket → ./backup/media-YYYYMMDD
```

Uploads go to `MEDIA_BUCKET` when it is set, otherwise to `MEDIA_DIR`.

## Security notes

- Only the `admin` role exists. Every `/api/v1/admin/*` route requires a live,
  non-revoked session belonging to an enabled admin.
- Page and profile HTML is rendered on the site as trusted markup, so an
  administrator can put any HTML (including script) on the site. That is
  intended for a single-team CMS. Only give admin access to people you would
  trust with the site's code.
- Uploads are type-checked from their bytes (JPEG/PNG/GIF/WebP/PDF), never
  from the filename. SVG is refused.
- The last active administrator cannot be disabled or deleted.
