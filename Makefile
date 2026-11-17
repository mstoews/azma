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

.DEFAULT_GOAL := help
.PHONY: help install secrets api web dev check-env migrate migrate-status admin media test build cloud-build deploy release

help: ## List the commands
	@awk 'BEGIN { FS = ":.*## " } /^[a-z-]+:.*## / { printf "  make %-15s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

install: ## Install website (npm) and API (Go) dependencies
	npm ci
	cd server && go mod download

secrets: ## Download secrets from Google Secret Manager into server/app.env
	PROJECT=$(PROJECT) ./scripts/fetch-secrets.sh

api: check-env ## Start the API server on :8080 (uses server/app.env)
	cd server && go run ./cmd/server

web: ## Start the website on :4200; /api and /media go to the API on :8080
	npx ng serve --port $(WEB_PORT)

dev: check-env ## Start the API and the website together (Ctrl-C stops both)
	@$(MAKE) --no-print-directory -j2 api web

check-env:
	@test -f $(ENV_FILE) || { echo "$(ENV_FILE) is missing. Run: make secrets"; exit 1; }
	@grep -Eq '^DB_SOURCE=.+' $(ENV_FILE) || { echo "DB_SOURCE is not set in $(ENV_FILE). Run: make secrets"; exit 1; }
	@! grep -Eqi '^AUTO_MIGRATE=(true|1)' $(ENV_FILE) || echo "Note: $(ENV_FILE) has AUTO_MIGRATE=true, so the API migrates the database on start. Set it to false to use make migrate instead."

migrate: check-env ## Apply pending database migrations to the DB in server/app.env (Neon)
	cd server && go run ./cmd/admin migrate up

migrate-status: check-env ## Show the database's schema version
	cd server && go run ./cmd/admin migrate version

admin: check-env ## Create or reset a CMS administrator: make admin EMAIL=you@example.com NAME="Your Name"
	@test -n "$(EMAIL)" || { echo 'Usage: make admin EMAIL=you@example.com NAME="Your Name"'; exit 1; }
	cd server && go run ./cmd/admin create -email "$(EMAIL)" -name "$(NAME)"

media: ## Download uploaded media from the Cloud Storage bucket into server/media
	cd server && ./media-sync.sh download ./media

test: ## Run the website and API tests
	npx ng test --watch=false
	cd server && go test ./...

build: ## Build the website (dist/) and the API binaries (server/bin/)
	npx ng build
	$(MAKE) -C server build

cloud-build: ## Build the site + API image in Cloud Build (tags: build id and latest)
	PROJECT=$(PROJECT) REGION=$(REGION) ./scripts/cloud-run.sh build

deploy: ## Deploy an image to Cloud Run: make deploy [TAG=<build-id>] (asks first; YES=1 skips)
	PROJECT=$(PROJECT) REGION=$(REGION) ./scripts/cloud-run.sh deploy $(TAG)

release: ## Build in Cloud Build, then deploy that exact build to Cloud Run (asks first)
	PROJECT=$(PROJECT) REGION=$(REGION) ./scripts/cloud-run.sh release
