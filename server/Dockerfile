# Builds the Angular site and the Go CMS server into one image.
# Build context is the repository root:  docker build -f server/Dockerfile .

FROM node:22-alpine AS site
WORKDIR /site
COPY package.json package-lock.json ./
RUN npm ci
COPY angular.json tsconfig*.json ./
COPY src ./src
COPY public ./public
RUN npx ng build

FROM golang:1.26-alpine AS server
WORKDIR /build
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /out/server ./cmd/server \
 && CGO_ENABLED=0 go build -ldflags="-s -w" -o /out/admin ./cmd/admin \
 && CGO_ENABLED=0 go build -ldflags="-s -w" -o /out/seed ./cmd/seed

FROM alpine:3.22
RUN adduser -D -u 10001 cms && mkdir -p /app/media && chown cms /app/media
WORKDIR /app
COPY --from=server /out/ ./
COPY --from=site /site/dist/azma-associates/browser ./site
# The seed command reads these to import the original content.
COPY src/app/data/site-data.json ./seed-data/site-data.json
COPY public/wp-content/uploads ./seed-data/uploads
ENV STATIC_DIR=/app/site MEDIA_DIR=/app/media ENVIRONMENT=production
USER cms
EXPOSE 8080
VOLUME /app/media
CMD ["./server"]
