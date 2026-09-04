#!/bin/sh
set -eu

VERSION="${WINMICE_VERSION:-0.0.0-dev}"
while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="${2:?--version requires a value}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done
case "$VERSION" in
  "") echo "Version must be non-empty" >&2; exit 1 ;;
esac

# EdDSA public key Sparkle uses to verify downloaded updates. Not a secret: it
# ships inside every copy of the app. Generated once with Sparkle's
# generate_keys; the matching private key is the SPARKLE_ED_PRIVATE_KEY repo
# secret. verify-bundle-metadata.sh refuses to pass while this is the placeholder.
SPARKLE_PUBLIC_ED_KEY="Tmdsz0zEHetxSYorQPZoQVFMEXypDhUl4rKOtf48ZBM="

swift build -c release

APP_DIR="dist/WinMice.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
ICONSET="dist/WinMice.iconset"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"

cp ".build/release/WinMice" "$MACOS/WinMice"
swift scripts/make-icons.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$RESOURCES/WinMice.icns"

# SwiftPM resolves Sparkle as a binary xcframework but never copies it into the
# bundle, so stage it by hand. The path embeds both the Sparkle version and the
# slice name, so discover it rather than hardcoding it.
SPARKLE_FRAMEWORK=$(find .build/artifacts -type d -name 'Sparkle.framework' -path '*macos*' | head -n 1)
[ -n "$SPARKLE_FRAMEWORK" ] || {
  echo "Sparkle.framework not found under .build/artifacts — run 'swift build -c release' first" >&2
  exit 1
}
# -R (not -r) preserves the framework's Versions/Current symlinks; flattening them
# invalidates the signature.
rm -rf "$FRAMEWORKS/Sparkle.framework"
cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS/Sparkle.framework"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WinMice</string>
    <key>CFBundleIdentifier</key>
    <string>cz.anibalribeiro.winmice</string>
    <key>CFBundleName</key>
    <string>WinMice</string>
    <key>CFBundleDisplayName</key>
    <string>WinMice</string>
    <key>CFBundleIconFile</key>
    <string>WinMice.icns</string>
    <key>CFBundleIconName</key>
    <string>WinMice</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>WinMice uses accessibility to bring the window under the cursor forward, post native scroll events, and handle back/forward navigation on your behalf.</string>
    <key>SUFeedURL</key>
    <string>https://github.com/anibalribeiro/WinMice/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_ED_KEY}</string>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
</dict>
</plist>
PLIST

ENTITLEMENTS="$(CDPATH= cd -- "$(dirname "$0")" && pwd)/WinMice.entitlements"
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  # Sparkle's helpers each carry their own signature, and --deep is not used here,
  # so they must be signed explicitly, inside-out, before the app bundle seals
  # their hashes. They deliberately do NOT get WinMice's entitlements: the
  # accessibility grant belongs to the app alone.
  SPARKLE_VERSIONED="$FRAMEWORKS/Sparkle.framework/Versions/B"
  for nested in \
    "$SPARKLE_VERSIONED"/XPCServices/*.xpc \
    "$SPARKLE_VERSIONED/Updater.app" \
    "$SPARKLE_VERSIONED/Autoupdate" \
    "$FRAMEWORKS/Sparkle.framework"
  do
    [ -e "$nested" ] || continue
    codesign --force --options runtime --timestamp \
      --sign "$CODESIGN_IDENTITY" \
      "$nested"
  done

  # --timestamp requests a secure timestamp explicitly; notarization requires
  # one, and codesign's unspecified default may skip it on some signatures.
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$CODESIGN_IDENTITY" \
    "$APP_DIR"
else
  if [ "${WINMICE_REQUIRE_DEVELOPER_ID:-0}" = "1" ]; then
    echo "CODESIGN_IDENTITY is required when WINMICE_REQUIRE_DEVELOPER_ID=1 (refusing to ad-hoc sign a release build)" >&2
    exit 1
  fi
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi
touch "$APP_DIR"

echo "Built $APP_DIR"
