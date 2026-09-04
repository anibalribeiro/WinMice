#!/bin/sh
set -eu

ZIP="${1:?usage: verify-packaged-zip.sh <path-to-zip>}"
[ -f "$ZIP" ] || { echo "missing zip: $ZIP" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ditto -x -k "$ZIP" "$TMP"

APP="$TMP/WinMice.app"
fail=0

[ -d "$APP" ] || { echo "WinMice.app is not at the root of $ZIP"; fail=1; }

# A precise, self-explanatory failure for exactly this defect class, rather
# than codesign's confusing "bundle format is ambiguous" once an archiver
# that follows symlinks has already flattened the framework.
if [ -d "$APP" ]; then
  [ -L "$APP/Contents/Frameworks/Sparkle.framework/Sparkle" ] || {
    echo "Contents/Frameworks/Sparkle.framework/Sparkle is not a symlink — archiver flattened Sparkle.framework"
    fail=1
  }
fi

./scripts/verify-sparkle-embedding.sh "$APP" || fail=1

if [ "$fail" -eq 0 ]; then
  echo "Verified packaged zip: $ZIP"
fi
exit "$fail"
