#!/usr/bin/env bash
# Deploys the latest built image to Cloud Run.
#
#   ./deploy.sh            # deploy :latest (build first with cloudbuild.yaml)
#   ./deploy.sh <build-id> # deploy a specific build, e.g. to roll back
#
# One-time setup this relies on (already done for web-azma):
#   bucket gs://web-azma-media, Artifact Registry repo "azma",
#   service account azma-cms-run, secret azma-db-source (the Neon DSN).
set -euo pipefail

PROJECT=${PROJECT:-web-azma}
REGION=${REGION:-asia-northeast1}
SERVICE=${SERVICE:-azma-cms}
TAG=${1:-latest}
IMAGE="$REGION-docker.pkg.dev/$PROJECT/azma/cms:$TAG"

gcloud run deploy "$SERVICE" \
  --project "$PROJECT" --region "$REGION" \
  --image "$IMAGE" \
  --service-account "azma-cms-run@$PROJECT.iam.gserviceaccount.com" \
  --set-secrets "DB_SOURCE=azma-db-source:latest" \
  --set-env-vars "ENVIRONMENT=production,MEDIA_BUCKET=web-azma-media,MEDIA_BUCKET_PREFIX=media/,STATIC_DIR=/app/site,AUTO_MIGRATE=true" \
  --allow-unauthenticated \
  --port 8080 --cpu 1 --memory 512Mi \
  --min-instances 0 --max-instances 3 --concurrency 80
