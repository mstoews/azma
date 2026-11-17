# AZMA website + CMS: day-to-day commands. Run `make` to list them.
#
# Local development runs the API and the website on this machine against the
# Neon database (used as UAT/test data, not live). The connection string is a
# secret in Google Secret Manager; `make secrets` copies it into server/app.env
# (git-ignored), which the API reads on start.
#
# First time:
#   gcloud auth login
#   make install secrets
# Then, in two terminals (or `make dev` for both in one):
#   make api      # API on http://localhost:8080
#   make web      # website on http://localhost:4200 (admin at /admin)
#
# Local database instead of Neon (Docker): start it, create the schema and
# load the original content once, then add DB=local to the usual commands:
#   make db-up migrate db-seed DB=local
#   make dev DB=local
#
# Releasing to Cloud Run (production, project web-azma):
#   make migrate  # only when the release adds database migrations
#   make release  # build the image in Cloud Build, then deploy that build
#
# The server never migrates the database on its own (AUTO_MIGRATE=false);
# server/app.env and Cloud Run use the same Neon database.

PROJECT  ?= web-azma
REGION   ?= asia-northeast1
WEB_PORT ?= 4200
TAG      ?= latest
ENV_FILE := server/app.env

# DB=neon (default): the database in server/app.env. DB=local: the PostgreSQL
# container from server/docker-compose.yaml (make db-up).
DB ?= neon
COMPOSE              := docker compose -f server/docker-compose.yaml
LOCAL_DB_SOURCE      := postgresql://cms:cms@localhost:55440/cms?sslmode=disable
LOCAL_TEST_DB_SOURCE := postgresql://cms:cms@localhost:55440/cms_test?sslmode=disable
ifeq ($(DB),local)
# The server reads app.env, but environment variables win.
export DB_SOURCE := $(LOCAL_DB_SOURCE)
else ifneq ($(DB),neon)
$(error DB must be neon or local, not "$(DB)")
endif

.DEFAULT_GOAL := help
.PHONY: help install secrets api web dev check-env migrate migrate-status admin media test build cloud-build deploy release \
        db-up db-down db-reset db-psql db-seed test-integration

help: ## List the commands
	@awk 'BEGIN { FS = ":.*## " } /^[a-z-]+:.*## / { printf "  make %-17s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

install: ## Install website (npm) and API (Go) dependencies
	npm ci
	cd server && go mod download

secrets: ## Download secrets from Google Secret Manager into server/app.env
	PROJECT=$(PROJECT) ./scripts/fetch-secrets.sh

api: check-env ## Start the API server on :8080 (DB=local: the Docker database)
	cd server && go run ./cmd/server

web: ## Start the website on :4200; /api and /media go to the API on :8080
	npx ng serve --port $(WEB_PORT)

dev: check-env ## Start the API and the website together (Ctrl-C stops both)
	@$(MAKE) --no-print-directory -j2 api web

check-env:
ifeq ($(DB),local)
	@echo "Using the local Docker database ($(LOCAL_DB_SOURCE:postgresql://cms:cms@%=%)); start it with: make db-up"
else
	@test -f $(ENV_FILE) || { echo "$(ENV_FILE) is missing. Run: make secrets"; exit 1; }
	@grep -Eq '^DB_SOURCE=.+' $(ENV_FILE) || { echo "DB_SOURCE is not set in $(ENV_FILE). Run: make secrets"; exit 1; }
	@! grep -Eqi '^AUTO_MIGRATE=(true|1)' $(ENV_FILE) || echo "Note: $(ENV_FILE) has AUTO_MIGRATE=true, so the API migrates the database on start. Set it to false to use make migrate instead."
endif

migrate: check-env ## Apply pending database migrations (Neon, or DB=local)
	cd server && go run ./cmd/admin migrate up

migrate-status: check-env ## Show the database's schema version
	cd server && go run ./cmd/admin migrate version

admin: check-env ## Create or reset a CMS administrator: make admin EMAIL=you@example.com NAME="Your Name"
	@test -n "$(EMAIL)" || { echo 'Usage: make admin EMAIL=you@example.com NAME="Your Name"'; exit 1; }
	cd server && go run ./cmd/admin create -email "$(EMAIL)" -name "$(NAME)"

media: ## Download uploaded media from the Cloud Storage bucket into server/media
	cd server && ./media-sync.sh download ./media

test: ## Run the website and API unit tests
	npx ng test --watch=false
	cd server && go test ./...

# ---------------------------------------------------------------- local database (Docker)

db-up: ## Start the local PostgreSQL container (localhost:55440) and wait until ready
	$(COMPOSE) up -d --wait db

db-down: ## Stop the local PostgreSQL container (data is kept)
	$(COMPOSE) stop db

db-reset: ## Delete the local database's data (and the local stack's media volume; asks first)
	@[ -n "$(YES)" ] || { printf 'Delete the local Docker database and its data? [y/N] '; read a; [ "$$a" = y ] || [ "$$a" = Y ]; } || { echo cancelled; exit 1; }
	$(COMPOSE) --profile app down -v

db-psql: ## Open psql in the local database
	$(COMPOSE) exec db psql -U cms -d cms

db-seed: ## Load the original site content into the local database (after: make migrate DB=local)
	cd server && DB_SOURCE='$(LOCAL_DB_SOURCE)' go run ./cmd/seed

test-integration: ## Run the API integration tests against a scratch database in the local container
	@$(COMPOSE) exec -T db psql -U cms -d cms -tAc "SELECT 1 FROM pg_database WHERE datname = 'cms_test'" | grep -q 1 \
	  || $(COMPOSE) exec -T db createdb -U cms cms_test
	cd server && TEST_DB_SOURCE='$(LOCAL_TEST_DB_SOURCE)' go test ./...

build: ## Build the website (dist/) and the API binaries (server/bin/)
	npx ng build
	$(MAKE) -C server build

cloud-build: ## Build the site + API image in Cloud Build (tags: build id and latest)
	PROJECT=$(PROJECT) REGION=$(REGION) ./scripts/cloud-run.sh build

deploy: ## Deploy an image to Cloud Run: make deploy [TAG=<build-id>] (asks first; YES=1 skips)
	PROJECT=$(PROJECT) REGION=$(REGION) ./scripts/cloud-run.sh deploy $(TAG)

release: ## Build in Cloud Build, then deploy that exact build to Cloud Run (asks first)
	PROJECT=$(PROJECT) REGION=$(REGION) ./scripts/cloud-run.sh release
