#!/usr/bin/env bash
# Downloads the CMS secrets from Google Secret Manager into server/app.env,
# so the API (and the website, through the dev proxy) run locally against the
# Neon database.
#
#   ./scripts/fetch-secrets.sh          # or: make secrets
#   PROJECT=other-project ./scripts/fetch-secrets.sh
#
# server/app.env is git-ignored. If it does not exist it is created from
# server/app.env.example. Only the secret keys below are replaced; every other
# local setting in the file is kept. The file is written with mode 600 and
# secret values are never printed.
#
# Requires gcloud, signed in with access to the project's secrets:
#   gcloud auth login
set -euo pipefail

PROJECT=${PROJECT:-web-azma}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ENV_FILE="$ROOT/server/app.env"
EXAMPLE="$ROOT/server/app.env.example"

# KEY=secret-name pairs (the same secrets Cloud Run uses; see server/deploy.sh).
SECRETS=(
  "DB_SOURCE=azma-db-source"
)

die() { echo "fetch-secrets: $*" >&2; exit 1; }

command -v gcloud >/dev/null || die "gcloud is not installed (https://cloud.google.com/sdk/docs/install)."
account=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -n1)
[[ -n "$account" ]] || die "gcloud is not signed in. Run: gcloud auth login"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$EXAMPLE" "$ENV_FILE"
  echo "Created server/app.env from app.env.example" >&2
fi

tmp=$(mktemp "$ENV_FILE.XXXXXX")
trap 'rm -f "$tmp"' EXIT
chmod 600 "$tmp"
cp "$ENV_FILE" "$tmp"

for pair in "${SECRETS[@]}"; do
  key=${pair%%=*}
  secret=${pair#*=}
  echo "Fetching secret $secret -> $key ($PROJECT, as $account)" >&2
  value=$(gcloud secrets versions access latest --secret "$secret" --project "$PROJECT") ||
    die "could not read secret $secret in project $PROJECT."
  [[ -n "$value" ]] || die "secret $secret is empty."
  [[ "$value" != *$'\n'* ]] || die "secret $secret spans several lines; app.env needs one line per key."

  # Replace the key's line (commented-out or not) or append it, leaving the rest alone.
  KEY="$key" VALUE="$value" awk '
    BEGIN { key = ENVIRON["KEY"]; line = key "=" ENVIRON["VALUE"]; done = 0 }
    $0 ~ "^[[:space:]]*#?[[:space:]]*" key "=" && !done { print line; done = 1; next }
    $0 ~ "^[[:space:]]*" key "=" { next }   # drop duplicates
    { print }
    END { if (!done) print line }
  ' "$tmp" >"$tmp.new"
  mv "$tmp.new" "$tmp"
done

chmod 600 "$tmp"
mv "$tmp" "$ENV_FILE"
trap - EXIT
echo "Updated server/app.env (${#SECRETS[@]} secret(s)). It is git-ignored; do not commit it." >&2
