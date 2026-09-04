#!/bin/sh
set -eu

VERSION="${1:?usage: package-dmg.sh <version>}"
APP_DIR="dist/WinMice.app"
STAGE="dist/dmg-root"
OUT="dist/WinMice-${VERSION}.dmg"
BG="docs/dmg/background.png"

[ -d "$APP_DIR" ] || { echo "Missing $APP_DIR — run build-app.sh first" >&2; exit 1; }
[ -f "$BG" ] || { echo "Missing $BG" >&2; exit 1; }
command -v create-dmg >/dev/null || { echo "create-dmg not on PATH (brew install create-dmg)" >&2; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP_DIR" "$STAGE/WinMice.app"
# Only the app is staged. Applications comes from --app-drop-link.
# INSTALL.txt is intentionally not on the disk image — it made the Finder
# window scroll and cluttered the classic two-icon installer. Gatekeeper steps
# live in README / release notes / docs/dmg/INSTALL.txt in the repo.

# create-dmg builds a read-write scratch image named rw.<pid>.<name> beside the
# output and, on its AppleScript failure path, detaches the volume but exits
# without deleting it. The pid means the name never collides, so this only ever
# leaks disk space — but a retried release leaves two behind in dist/.
remove_scratch_images() {
  rm -f dist/rw.*."$(basename "$OUT")"
}
trap remove_scratch_images EXIT

remove_scratch_images
rm -f "$OUT"

create_image() {
  create-dmg "$@" \
    --volname "WinMice ${VERSION}" \
    --background "$BG" \
    --window-pos 200 120 \
    --window-size 600 440 \
    --icon-size 128 \
    --text-size 12 \
    --icon "WinMice.app" 150 190 \
    --hide-extension "WinMice.app" \
    --app-drop-link 450 190 \
    --no-internet-enable \
    "$OUT" \
    "$STAGE"
}

if ! create_image; then
  echo "WARNING: styled create-dmg failed; retrying with --skip-jenkins (visual styling was skipped)" >&2
  # create-dmg can leave a partial image after a failed Finder AppleEvents step.
  rm -f "$OUT"
  if ! create_image --skip-jenkins; then
    echo "create-dmg failed in both styled and headless modes" >&2
    exit 1
  fi
fi

[ -f "$OUT" ] || { echo "create-dmg did not produce $OUT" >&2; exit 1; }
echo "Wrote $OUT"
