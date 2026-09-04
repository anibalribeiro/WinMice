#!/bin/sh
set -eu

# Notarizes and staples a single release artifact.
#
# If TARGET is a directory (e.g. WinMice.app), it is zipped with `ditto` for
# submission (notarytool does not accept bundles directly) and stapled in
# place afterwards. Any other file (e.g. a .dmg) is submitted and stapled
# directly.
#
# notarytool submit --wait exits 0 even when status is Invalid/Rejected, and
# exits non-zero (e.g. 124) when --timeout fires while still In Progress.
# This script always inspects JSON / polls `notarytool info`, and fails closed
# unless status is Accepted. On Invalid/Rejected it dumps `notarytool log`.

TARGET="${1:?usage: notarize-file.sh <path-to-.app-or-.dmg>}"
[ -e "$TARGET" ] || { echo "missing target: $TARGET" >&2; exit 1; }

KEY_ID="${APPLE_API_KEY_ID:?APPLE_API_KEY_ID is required}"
ISSUER="${APPLE_API_ISSUER_ID:?APPLE_API_ISSUER_ID is required}"
KEY_P8="${APPLE_API_KEY_P8:?APPLE_API_KEY_P8 is required}"
TEAM_ID="${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"

TMP="${RUNNER_TEMP:-$(mktemp -d)}"
KEY_PATH="$TMP/AuthKey_${KEY_ID}.p8"
ZIP_PATH="$TMP/$(basename "$TARGET").notarize.zip"
RESULT_JSON="$TMP/$(basename "$TARGET").notary.json"
INFO_JSON="$TMP/$(basename "$TARGET").notary-info.json"

cleanup() {
  rm -f "$KEY_PATH" "$ZIP_PATH" "$RESULT_JSON" "$INFO_JSON"
}
trap cleanup EXIT HUP INT TERM

json_field() {
  /usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$1" "$2"
}

umask 077
printf '%s\n' "$KEY_P8" > "$KEY_PATH"
chmod 600 "$KEY_PATH"

if [ -d "$TARGET" ]; then
  TARGET_DIR="$(CDPATH='' cd -- "$(dirname "$TARGET")" && pwd)"
  TARGET_BASE="$(basename "$TARGET")"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$TARGET_DIR/$TARGET_BASE" "$ZIP_PATH"
  SUBMIT_PATH="$ZIP_PATH"
else
  SUBMIT_PATH="$TARGET"
fi

# First submissions (and busy periods) can exceed 30m. Allow a long wait, then
# poll `notarytool info` if Apple is still processing when --timeout fires.
set +e
xcrun notarytool submit "$SUBMIT_PATH" \
  --key "$KEY_PATH" \
  --key-id "$KEY_ID" \
  --issuer "$ISSUER" \
  --wait \
  --timeout 45m \
  --output-format json >"$RESULT_JSON"
SUBMIT_RC=$?
set -e

STATUS="$(json_field "$RESULT_JSON" status)"
SUBMISSION_ID="$(json_field "$RESULT_JSON" id)"

# Timeout responses often omit status but include id — keep polling.
polls=0
while [ "$STATUS" != "Accepted" ] && [ "$STATUS" != "Invalid" ] && [ "$STATUS" != "Rejected" ]; do
  if [ -z "$SUBMISSION_ID" ]; then
    echo "notarytool submit failed without a submission id (exit $SUBMIT_RC)" >&2
    cat "$RESULT_JSON" >&2 || true
    exit 1
  fi
  if [ "$polls" -ge 40 ]; then
    echo "gave up waiting for notarytool id=$SUBMISSION_ID after submit exit $SUBMIT_RC (last status='$STATUS')" >&2
    cat "$RESULT_JSON" >&2 || true
    exit 1
  fi
  echo "notarytool still pending (status='${STATUS:-unknown}', submit_exit=$SUBMIT_RC); polling id=$SUBMISSION_ID ..." >&2
  sleep 30
  xcrun notarytool info "$SUBMISSION_ID" \
    --key "$KEY_PATH" \
    --key-id "$KEY_ID" \
    --issuer "$ISSUER" \
    --output-format json >"$INFO_JSON"
  STATUS="$(json_field "$INFO_JSON" status)"
  polls=$((polls + 1))
done

if [ "$STATUS" != "Accepted" ]; then
  echo "notarytool status was '$STATUS' (want Accepted); submission id=$SUBMISSION_ID" >&2
  cat "$RESULT_JSON" >&2 || true
  cat "$INFO_JSON" >&2 || true
  echo "---- notarytool log ----" >&2
  xcrun notarytool log "$SUBMISSION_ID" \
    --key "$KEY_PATH" \
    --key-id "$KEY_ID" \
    --issuer "$ISSUER" >&2 || true
  exit 1
fi

xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"

echo "Notarized and stapled $TARGET (team $TEAM_ID; id=$SUBMISSION_ID)"
