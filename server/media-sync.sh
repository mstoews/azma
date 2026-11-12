#!/usr/bin/env bash
# Moves uploaded media between local disk and the Cloud Storage bucket.
#
#   ./media-sync.sh upload   [dir]   # local dir (default ./media) -> bucket
#   ./media-sync.sh download [dir]   # bucket -> local dir (default ./backup/media-YYYYMMDD)
#
# Object keys mirror the local layout (2026/11/abcd-photo.jpg), so a folder
# written by the server with MEDIA_DIR maps 1:1 onto the bucket. Neither
# direction deletes anything at the destination.
set -euo pipefail

BUCKET=${MEDIA_BUCKET:-web-azma-media}
PREFIX=${MEDIA_BUCKET_PREFIX:-media/}
DEST="gs://$BUCKET/${PREFIX%/}"

case "${1:-}" in
  upload)
    SRC=${2:-./media}
    gcloud storage rsync --recursive --exclude='(^|/)\.' "$SRC" "$DEST"
    ;;
  download)
    OUT=${2:-./backup/media-$(date +%Y%m%d)}
    mkdir -p "$OUT"
    gcloud storage rsync --recursive "$DEST" "$OUT"
    echo "downloaded to $OUT"
    ;;
  *)
    sed -n '2,9p' "$0"; exit 2 ;;
esac
