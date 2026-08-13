#!/usr/bin/env bash
# Wrapper around ApiGen's REST API (POST /generator/file).
# Usage: apigen-api.sh <openapi-path> -o <outdir> [--url <api-url>] [--unzip]
#
# Required env var: APIGEN_API_KEY (sent as the `apikey` header). Never pass
# the key as a CLI flag or hardcode it here — it must only ever live in the
# environment.
# Required (env var or flag): the target URL. APIGEN_API_URL, or --url. No
# default — there is no "well-known" endpoint; caller must always say which
# deployment to hit.

set -euo pipefail

SPEC=""
OUTDIR="./out"
UNZIP=0
URL="${APIGEN_API_URL:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--outpath)
      OUTDIR="$2"; shift 2 ;;
    --url)
      URL="$2"; shift 2 ;;
    --unzip)
      UNZIP=1; shift ;;
    -*)
      echo "Unknown flag: $1" >&2; exit 1 ;;
    *)
      SPEC="$1"; shift ;;
  esac
done

if [ -z "$SPEC" ]; then
  echo "Usage: apigen-api.sh <openapi-path> -o <outdir> --url <api-url> [--unzip]" >&2
  exit 1
fi

if [ ! -f "$SPEC" ]; then
  echo "Spec not found: $SPEC" >&2
  exit 1
fi

if [ -z "${APIGEN_API_KEY:-}" ]; then
  echo "APIGEN_API_KEY is not set. Export it before running this script:" >&2
  echo '  export APIGEN_API_KEY="<your-key>"' >&2
  exit 1
fi

if [ -z "$URL" ]; then
  echo "No target URL given. Set APIGEN_API_URL or pass --url <api-url>:" >&2
  echo '  export APIGEN_API_URL="<deployed-endpoint>"' >&2
  echo "  # or: apigen-api.sh <spec> -o <outdir> --url <deployed-endpoint>" >&2
  exit 1
fi

mkdir -p "$OUTDIR"

BASENAME="$(basename "$SPEC")"
NAME="${BASENAME%.*}"
ZIP_PATH="$OUTDIR/$NAME.zip"
BODY_TMP="$(mktemp)"
trap 'rm -f "$BODY_TMP"' EXIT

echo "POST $URL"
echo "  file=$SPEC"

HTTP_STATUS=$(curl -sS -o "$BODY_TMP" -w '%{http_code}' -X POST "$URL" \
  -H 'accept: */*' \
  -H "apikey: ${APIGEN_API_KEY}" \
  -H 'Content-Type: multipart/form-data' \
  -F "file=@${SPEC}")

if [ "$HTTP_STATUS" != "200" ]; then
  echo "Request failed (HTTP $HTTP_STATUS):" >&2
  cat "$BODY_TMP" >&2
  exit 1
fi

mv "$BODY_TMP" "$ZIP_PATH"
trap - EXIT
echo "OK -> $ZIP_PATH"

if [ "$UNZIP" -eq 1 ]; then
  DEST="$OUTDIR/$NAME"
  unzip -o "$ZIP_PATH" -d "$DEST" >/dev/null
  echo "Unzipped -> $DEST"
fi
