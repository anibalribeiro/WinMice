#!/bin/sh
set -eu

VERSION="${1:?usage: package-release.sh <version>}"
APP_DIR="dist/WinMice.app"
OUT="dist/WinMice-${VERSION}.zip"

[ -d "$APP_DIR" ] || { echo "Missing $APP_DIR — run build-app.sh first" >&2; exit 1; }

rm -f "$OUT"
# Must preserve Sparkle.framework's symlinks verbatim, or the extracted app's
# signature no longer validates. ditto does; plain zip -r -X does not.
( cd dist && ditto -c -k --keepParent WinMice.app "$(basename "$OUT")" )

echo "Wrote $OUT"
