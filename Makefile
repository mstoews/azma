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

PROJECT  ?= web-azma
WEB_PORT ?= 4200
ENV_FILE := server/app.env

.DEFAULT_GOAL := help
.PHONY: help install secrets api web dev check-env admin media test build

help: ## List the commands
	@awk 'BEGIN { FS = ":.*## " } /^[a-z-]+:.*## / { printf "  make %-9s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

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
