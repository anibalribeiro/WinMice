#!/bin/sh
set -eu

VERSION="${1:?usage: generate-appcast.sh <version> <zip> <changelog.md>}"
ZIP="${2:?usage: generate-appcast.sh <version> <zip> <changelog.md>}"
CHANGELOG="${3:?usage: generate-appcast.sh <version> <zip> <changelog.md>}"
KEY_FILE="${SPARKLE_ED_KEY_FILE:?SPARKLE_ED_KEY_FILE must point at the exported EdDSA private key}"
TEMPLATE="docs/appcast-template.xml"
OUT="dist/appcast.xml"

[ -f "$TEMPLATE" ] || { echo "missing $TEMPLATE" >&2; exit 1; }
[ -f "$ZIP" ] || { echo "missing zip: $ZIP" >&2; exit 1; }
[ -f "$CHANGELOG" ] || { echo "missing changelog: $CHANGELOG" >&2; exit 1; }
[ -f "$KEY_FILE" ] || { echo "missing key file: $KEY_FILE" >&2; exit 1; }

# Sparkle ships sign_update inside the SPM artifact tree that swift build already
# resolved, so there is nothing extra to download.
SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-}"
if [ -z "$SIGN_UPDATE" ]; then
  # Sparkle ships two sign_update binaries: the EdDSA one in bin/, and a
  # deprecated DSA script in bin/old_dsa_scripts/. Exclude the latter so the
  # right tool is chosen by name rather than by find's traversal order, and
  # refuse to guess if the layout ever changes.
  MATCHES=$(find .build/artifacts -type f -name sign_update -not -path '*old_dsa_scripts*')
  COUNT=$(printf '%s\n' "$MATCHES" | grep -c . || true)
  if [ "$COUNT" -ne 1 ]; then
    echo "expected exactly one sign_update under .build/artifacts, found $COUNT" >&2
    printf '%s\n' "$MATCHES" >&2
    echo "run 'swift build -c release' first, or set SPARKLE_SIGN_UPDATE" >&2
    exit 1
  fi
  SIGN_UPDATE="$MATCHES"
fi

# The key must be passed as a file, not inline: sign_update defaults to the login
# Keychain, which does not exist on a CI runner, and an inline key would show up
# in the process list.
FRAGMENT=$("$SIGN_UPDATE" -f "$KEY_FILE" "$ZIP")
ED_SIGNATURE=$(printf '%s' "$FRAGMENT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(printf '%s' "$FRAGMENT" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')
[ -n "$ED_SIGNATURE" ] || { echo "sign_update produced no signature: $FRAGMENT" >&2; exit 1; }
[ -n "$LENGTH" ] || { echo "sign_update produced no length: $FRAGMENT" >&2; exit 1; }

PUBDATE=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')

mkdir -p dist
awk -v version="$VERSION" \
    -v sig="$ED_SIGNATURE" \
    -v len="$LENGTH" \
    -v pubdate="$PUBDATE" \
    -v changelog="$CHANGELOG" '
  $0 ~ /^[[:space:]]*\{\{CHANGES\}\}[[:space:]]*$/ {
    while ((getline line < changelog) > 0) print line
    close(changelog)
    next
  }
  {
    gsub(/\{\{VERSION\}\}/, version)
    gsub(/\{\{ED_SIGNATURE\}\}/, sig)
    gsub(/\{\{LENGTH\}\}/, len)
    gsub(/\{\{PUBDATE\}\}/, pubdate)
    print
  }
' "$TEMPLATE" > "$OUT"

if grep -q '{{' "$OUT"; then
  echo "unsubstituted placeholder left in $OUT" >&2
  exit 1
fi

echo "Wrote $OUT"
