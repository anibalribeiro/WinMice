#!/bin/sh
set -eu

APP="${1:?usage: verify-sparkle-embedding.sh <WinMice.app>}"
[ -d "$APP" ] || { echo "missing app bundle: $APP" >&2; exit 1; }

FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
BINARY="$APP/Contents/MacOS/WinMice"
fail=0

[ -d "$FRAMEWORK" ] || { echo "missing $FRAMEWORK"; fail=1; }
[ -f "$FRAMEWORK/Versions/B/Sparkle" ] || { echo "missing Sparkle binary in $FRAMEWORK"; fail=1; }

# A missing rpath still links and still signs; it only fails at launch.
if ! otool -l "$BINARY" | grep -q '@loader_path/../Frameworks'; then
  echo "main binary is missing an LC_RPATH of @loader_path/../Frameworks"
  fail=1
fi

# Seals the framework's hashes into the app signature; catches a nested binary
# signed after the outer bundle.
codesign --verify --deep --strict --verbose=2 "$APP" || fail=1

# Nested signature checks only apply to release builds; ad-hoc local builds have
# no Developer ID and no hardened runtime.
if codesign -dv --verbose=4 "$APP" 2>&1 | grep -q 'Signature=adhoc'; then
  echo "ad-hoc build: skipping Developer ID and hardened-runtime checks on nested code"
  exit "$fail"
fi

SPARKLE_VERSIONED="$FRAMEWORK/Versions/B"
for nested in \
  "$FRAMEWORK" \
  "$SPARKLE_VERSIONED"/XPCServices/*.xpc \
  "$SPARKLE_VERSIONED/Updater.app" \
  "$SPARKLE_VERSIONED/Autoupdate"
do
  [ -e "$nested" ] || continue
  INFO=$(codesign -dv --verbose=4 "$nested" 2>&1 || true)
  printf '%s\n' "$INFO" | grep -q 'Developer ID Application' || {
    echo "$nested: expected Developer ID Application identity"
    fail=1
  }
  # Every other check here only detects the *absence* of a proper signature, so
  # none of them can tell our signature apart from anyone else's Developer ID.
  # The team identifier is the only field that positively identifies ours. That
  # matters because build-app.sh hardcodes Versions/B and skips missing paths:
  # if Sparkle restructures, its nested signing loop signs nothing and the app
  # signature then seals code we never signed. The pinned 2.9.6 SwiftPM artifact
  # ships ad-hoc, so the checks above happen to catch that case today; this one
  # keeps catching it if a future artifact arrives already Developer ID signed.
  if [ -n "${APPLE_TEAM_ID:-}" ]; then
    printf '%s\n' "$INFO" | grep -q "^TeamIdentifier=${APPLE_TEAM_ID}$" || {
      echo "$nested: expected TeamIdentifier=${APPLE_TEAM_ID}, got: $(printf '%s\n' "$INFO" | grep '^TeamIdentifier=' || echo 'none')"
      fail=1
    }
  fi
  printf '%s\n' "$INFO" | grep -q 'flags=.*runtime' || {
    echo "$nested: expected hardened runtime"
    fail=1
  }
  printf '%s\n' "$INFO" | grep -q '^Timestamp=' || {
    echo "$nested: expected a secure timestamp"
    fail=1
  }
  if printf '%s\n' "$INFO" | grep -q 'Signature=adhoc'; then
    echo "$nested: refusing ad-hoc signature"
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "Verified Sparkle embedding: $APP"
fi
exit "$fail"
