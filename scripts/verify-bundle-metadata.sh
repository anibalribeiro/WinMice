#!/bin/sh
set -eu

APP="${1:?usage: verify-bundle-metadata.sh <WinMice.app> <expected-version>}"
EXPECTED_VERSION="${2:?usage: verify-bundle-metadata.sh <WinMice.app> <expected-version>}"
PLIST="$APP/Contents/Info.plist"
EXPECTED_ID="cz.anibalribeiro.winmice"
EXPECTED_FEED="https://github.com/anibalribeiro/WinMice/releases/latest/download/appcast.xml"

ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")
SHORT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")
FEED=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$PLIST" 2>/dev/null || echo "")
ED_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST" 2>/dev/null || echo "")
INTERVAL=$(/usr/libexec/PlistBuddy -c 'Print :SUScheduledCheckInterval' "$PLIST" 2>/dev/null || echo "")

fail=0
[ "$ID" = "$EXPECTED_ID" ] || { echo "CFBundleIdentifier: got '$ID' want '$EXPECTED_ID'"; fail=1; }
[ "$SHORT" = "$EXPECTED_VERSION" ] || { echo "CFBundleShortVersionString: got '$SHORT' want '$EXPECTED_VERSION'"; fail=1; }
[ "$BUILD" = "$EXPECTED_VERSION" ] || { echo "CFBundleVersion: got '$BUILD' want '$EXPECTED_VERSION'"; fail=1; }
[ "$FEED" = "$EXPECTED_FEED" ] || { echo "SUFeedURL: got '$FEED' want '$EXPECTED_FEED'"; fail=1; }
[ "$INTERVAL" = "86400" ] || { echo "SUScheduledCheckInterval: got '$INTERVAL' want '86400'"; fail=1; }

# An ed25519 public key is 32 bytes, so 44 base64 characters. This also catches
# the unreplaced placeholder from build-app.sh.
case "$ED_KEY" in
  REPLACE_WITH_GENERATED_PUBLIC_KEY|"")
    echo "SUPublicEDKey is unset or still the placeholder — run Sparkle's generate_keys and set SPARKLE_PUBLIC_ED_KEY in build-app.sh"
    fail=1
    ;;
  *)
    [ "${#ED_KEY}" -eq 44 ] || { echo "SUPublicEDKey: expected 44 base64 characters, got ${#ED_KEY}"; fail=1; }
    ;;
esac

# Absent on purpose: Sparkle only shows its first-launch permission prompt when
# this key is missing entirely.
if /usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' "$PLIST" >/dev/null 2>&1; then
  echo "SUEnableAutomaticChecks must not be set — its absence is what produces the permission prompt"
  fail=1
fi

# WinMice ships arm64-only, which is a deliberate product decision. Assert the
# slice so a misconfigured runner or a bad cross-build cannot publish an app
# that will not launch on the machines the cask installs it on.
BIN="$APP/Contents/MacOS/WinMice"
if [ ! -f "$BIN" ]; then
  echo "app binary missing: $BIN"
  fail=1
else
  ARCHS=$(lipo -archs "$BIN")
  case " $ARCHS " in
    *" arm64 "*) ;;
    *) echo "app binary has no arm64 slice (got '$ARCHS')"; fail=1 ;;
  esac
fi

exit "$fail"
