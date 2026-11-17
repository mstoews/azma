#!/usr/bin/env bash
# Builds the site + API image with Cloud Build and deploys it to Cloud Run.
#
#   ./scripts/cloud-run.sh build            # make cloud-build
#   ./scripts/cloud-run.sh deploy [TAG]     # make deploy [TAG=<build-id>]   (default: latest)
#   ./scripts/cloud-run.sh release          # make release: build, then deploy that exact build
#
# Settings (environment): PROJECT (web-azma), REGION (asia-northeast1),
# SERVICE (azma-cms). YES=1 skips the confirmation before deploying;
# ALLOW_DIRTY=1 allows building with uncommitted changes.
#
# Cloud Build uploads the working tree minus .gcloudignore (which keeps out
# server/app.env and other secrets, node_modules, dist, local media), builds
# server/Dockerfile and pushes the image tagged with the build id and
# "latest" (server/cloudbuild.yaml). Deploying runs server/deploy.sh.
#
# Requires gcloud, signed in with access to the project: gcloud auth login
set -euo pipefail

PROJECT=${PROJECT:-web-azma}
REGION=${REGION:-asia-northeast1}
SERVICE=${SERVICE:-azma-cms}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

die() { echo "cloud-run: $*" >&2; exit 1; }

require_gcloud() {
  command -v gcloud >/dev/null || die "gcloud is not installed (https://cloud.google.com/sdk/docs/install)."
  ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -n1)
  [[ -n "$ACCOUNT" ]] || die "gcloud is not signed in. Run: gcloud auth login"
}

# What is being built, for the log and the confirmation prompt.
describe_source() {
  if git rev-parse --git-dir >/dev/null 2>&1; then
    local dirty=""
    [[ -z "$(git status --porcelain)" ]] || dirty=" + uncommitted changes"
    echo "$(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD)$dirty"
  else
    echo "working tree (not a git checkout)"
  fi
}

require_clean() {
  git rev-parse --git-dir >/dev/null 2>&1 || return 0
  if [[ -n "$(git status --porcelain)" && -z "${ALLOW_DIRTY:-}" ]]; then
    git status --short >&2
    die "uncommitted changes would be built into the image. Commit or stash them, or set ALLOW_DIRTY=1."
  fi
}

confirm_deploy() {
  local tag=$1
  echo "About to deploy to Cloud Run:" >&2
  echo "  service  $SERVICE ($PROJECT, $REGION)" >&2
  echo "  image    $REGION-docker.pkg.dev/$PROJECT/azma/cms:$tag" >&2
  echo "  as       $ACCOUNT" >&2
  [[ -n "${YES:-}" ]] && return 0
  [[ -t 0 ]] || die "not a terminal; set YES=1 to deploy without the prompt."
  local answer
  read -r -p "Deploy? [y/N] " answer
  [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]] || die "cancelled."
}

# Submits the build, streams its log, and prints the build id on stdout once it succeeded.
build() {
  require_gcloud
  require_clean
  echo "Building $(describe_source) in Cloud Build ($PROJECT, as $ACCOUNT)..." >&2
  local id status
  id=$(gcloud builds submit --config server/cloudbuild.yaml --project "$PROJECT" --region "$REGION" \
        --async --format='value(id)' .)
  [[ -n "$id" ]] || die "Cloud Build did not return a build id."
  echo "Build $id started; streaming its log." >&2
  gcloud builds log --stream "$id" --project "$PROJECT" --region "$REGION" >&2 ||
    echo "(Could not stream the log; waiting for the build to finish.)" >&2
  while :; do
    status=$(gcloud builds describe "$id" --project "$PROJECT" --region "$REGION" --format='value(status)')
    [[ "$status" == QUEUED || "$status" == PENDING || "$status" == WORKING ]] || break
    sleep ${POLL:-10}
  done
  [[ "$status" == "SUCCESS" ]] || die "build $id finished with status $status."
  echo "Build $id succeeded: image tags $id and latest." >&2
  echo "$id"
}

deploy() {
  local tag=${1:-latest}
  require_gcloud
  confirm_deploy "$tag"
  PROJECT=$PROJECT REGION=$REGION SERVICE=$SERVICE ./server/deploy.sh "$tag"
  local url
  url=$(gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" --format='value(status.url)' 2>/dev/null || true)
  echo "Deployed $tag to $SERVICE${url:+: $url}" >&2
}

case "${1:-}" in
  build)   build >/dev/null ;;
  deploy)  deploy "${2:-latest}" ;;
  release)
    id=$(build)
    # Deploy the exact image just built, not "latest", which another build could move.
    deploy "$id"
    ;;
  *) sed -n '2,15p' "$0" >&2; exit 2 ;;
esac
