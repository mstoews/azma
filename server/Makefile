# AZMA CMS server. Run targets from server/.

.PHONY: devdb run migrate migrate-down seed admin sqlc test build docker

devdb:          ## local PostgreSQL without Docker (prints DB_SOURCE)
	go run ./cmd/devdb

run:            ## API on :8080 (applies migrations when AUTO_MIGRATE=true)
	go run ./cmd/server

migrate:
	go run ./cmd/admin migrate up

migrate-down:
	go run ./cmd/admin migrate down

seed:           ## import the current static site content
	go run ./cmd/seed

admin:          ## make admin EMAIL=you@example.com NAME="Your Name"
	go run ./cmd/admin create -email "$(EMAIL)" -name "$(NAME)"

sqlc:           ## regenerate db/sqlc from db/query + db/migration
	sqlc generate

test:
	go test ./...

build:
	CGO_ENABLED=0 go build -ldflags="-s -w" -o bin/server ./cmd/server
	CGO_ENABLED=0 go build -ldflags="-s -w" -o bin/admin ./cmd/admin
	CGO_ENABLED=0 go build -ldflags="-s -w" -o bin/seed ./cmd/seed

docker:         ## site + API image, built from the repo root
	docker build -f Dockerfile -t azma-cms ..
