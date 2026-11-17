# AZMA CMS server

Go API that stores the AZMA & Associates site content in PostgreSQL and lets
administrators edit it. The Angular app in the repo root reads published
content from `GET /api/v1/site` and has the admin UI at `/admin`.

It is also the backend for the iOS app in `ios/`: candidate profiles and
resumes, the positions clients ask us to fill, and consultation requests.

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

The usual way is from the repo root, against Neon (UAT/test data):
`make secrets`, then `make api` and `make web`. See the root README.

To use a local database instead (embedded PostgreSQL; it cannot run as
root, so not in root-only containers):

```sh
cd server
cp app.env.example app.env        # DB_SOURCE defaults to the devdb DSN
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

### The web site and the CMS

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

### Languages

Content is written in English and can be translated into the languages in
`api.supportedLocales` (currently `ja`). Translations live in their own tables
(migration `000003`); images, slugs and the published flag are shared.

- `GET /api/v1/site?lang=ja` returns Japanese wherever it exists and English
  for anything not translated, field by field. Without `lang` the server uses
  `Accept-Language`; the response's `locale` says which language was chosen.
  The web site asks for `lang=en`; the iOS app asks for its own language.
- A menu item with no translated label takes its page's translated title.
- Admin pages, profiles and settings carry a `translations` object keyed by
  locale, and menu items carry `labels`. A request sets the locales it names;
  a locale with every field blank is removed; locales left out, or a request
  without the field, are not touched.

### Recruitment (the mobile app)

| Method | Path | Who |
|---|---|---|
| GET | `/api/v1/jobs`, `/jobs/:id` | public; published positions only |
| GET | `/api/v1/options` | public; the values every picker offers |
| POST | `/api/v1/auth/register` | public; `candidate` or `employer` only, rate limited |
| POST | `/api/v1/inquiries` | public; consultation requests, rate limited |
| GET | `/api/v1/my/inquiries` | signed in |
| GET | `/api/v1/resumes/:id/file` | the owner, or an administrator |
| GET/PUT | `/api/v1/candidate/me`, `/profile` (+ `POST /profile/submit`) | candidate |
| GET/POST/DELETE | `/api/v1/candidate/resumes` | candidate |
| POST | `/api/v1/candidate/applications` (+ `…/:id/withdraw`) | candidate |
| PUT/DELETE | `/api/v1/candidate/saved-jobs/:id` | candidate |
| GET/PUT | `/api/v1/employer/me`, `/profile` | employer |
| CRUD | `/api/v1/employer/jobs` (+ `PUT …/:id/status`) | employer |
| GET/PUT | `/api/v1/employer/jobs/:id/applications`, `/employer/applications/:id/status` | employer |
| GET/PUT | `/api/v1/admin/jobs` (+ `…/:id/status`, `…/:id/applications`) | admin |
| PUT | `/api/v1/admin/applications/:id/status` | admin |
| GET | `/api/v1/admin/candidates` (+ `/:id`) | admin |
| GET/PUT | `/api/v1/admin/inquiries` (+ `…/:id/status`) | admin |

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

## How a search runs

The states a posting and an application move through are the firm's own
process, not a generic job board:

- A client writes a posting as a **draft**, then submits it. It sits at
  **pending** until a consultant **publishes** it or sends it back
  (**rejected**) with a note the client sees. Editing a live posting takes it
  back to review, so what candidates read is always what a consultant approved.
- A confidential posting is published without the client's name: candidates see
  "Confidential client", consultants see the client.
- A candidate fills in a profile and uploads a resume, then asks to be
  **represented**, which is what puts them in front of a consultant.
- An application starts at **submitted**. The client sees the applicant's
  professional summary but *not* their name, email or resume until a consultant
  moves it to **shortlisted** — the app's version of presenting a shortlist.
  Only an administrator can make that move, and only an administrator can
  download the document. A client records their own decisions from
  `under_review` onward.

## Security notes

- Roles are `admin`, `candidate` and `employer`. Every `/api/v1/admin/*` route
  requires a live, non-revoked session belonging to an enabled admin;
  `/candidate/*` and `/employer/*` require that role and nothing more.
- Resumes are **not** media. They live under `resumes/` in the same object
  store but are never served from a public path: `GET /api/v1/resumes/:id/file`
  checks the caller owns the document or is an administrator, serves it
  `private, no-store` as an attachment, and audits a consultant's download.
- Uploaded resumes are checked by their bytes (PDF header, OLE2 or ZIP
  container) with the extension only used to tell `.doc` from `.docx`.
- `/api/v1/admin/users` manages administrators only. Candidate and employer
  accounts are app users, not people with CMS access, and are listed through
  `/api/v1/admin/candidates`.
- Page and profile HTML is rendered on the site as trusted markup, so an
  administrator can put any HTML (including script) on the site. That is
  intended for a single-team CMS. Only give admin access to people you would
  trust with the site's code.
- Uploads are type-checked from their bytes (JPEG/PNG/GIF/WebP/PDF), never
  from the filename. SVG is refused.
- The last active administrator cannot be disabled or deleted.
