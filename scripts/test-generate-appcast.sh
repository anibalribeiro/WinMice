#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/project/docs" "$TMP/project/dist" "$TMP/bin"
cp "$ROOT/docs/appcast-template.xml" "$TMP/project/docs/appcast-template.xml"
printf 'zip contents\n' > "$TMP/project/dist/WinMice-9.9.9.zip"
printf -- '- Added a thing.\n- Fixed another thing.\n' > "$TMP/project/docs/changelog-9.9.9.md"
printf 'not-a-real-private-key\n' > "$TMP/key"

cat > "$TMP/bin/sign_update" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$TEST_STATE/sign_update_args"
printf 'sparkle:edSignature="dGVzdHNpZ25hdHVyZQ==" length="4242"\n'
EOF
chmod +x "$TMP/bin/sign_update"

export TEST_STATE="$TMP"
export SPARKLE_SIGN_UPDATE="$TMP/bin/sign_update"
export SPARKLE_ED_KEY_FILE="$TMP/key"

if ! (
  cd "$TMP/project"
  "$ROOT/scripts/generate-appcast.sh" 9.9.9 dist/WinMice-9.9.9.zip docs/changelog-9.9.9.md
) >"$TMP/stdout" 2>"$TMP/stderr"; then
  printf 'generate-appcast unexpectedly failed\n' >&2
  cat "$TMP/stderr" >&2
  exit 1
fi

OUT="$TMP/project/dist/appcast.xml"
[ -f "$OUT" ] || { echo "no appcast written" >&2; exit 1; }

grep -q '<sparkle:version>9.9.9</sparkle:version>' "$OUT"
grep -q 'releases/download/v9.9.9/WinMice-9.9.9.zip' "$OUT"
grep -q 'sparkle:edSignature="dGVzdHNpZ25hdHVyZQ=="' "$OUT"
grep -q 'length="4242"' "$OUT"
grep -q 'sparkle:format="markdown"' "$OUT"
grep -q -- '- Added a thing.' "$OUT"
grep -q -- '- Fixed another thing.' "$OUT"
if grep -q '{{' "$OUT"; then
  echo "unsubstituted placeholder in appcast" >&2
  exit 1
fi
xmllint --noout "$OUT"

# The private key must be handed over as a file, never inline.
grep -q -- '-f' "$TMP/sign_update_args"
if grep -q 'not-a-real-private-key' "$TMP/sign_update_args"; then
  echo "private key contents leaked into the sign_update command line" >&2
  exit 1
fi

# Missing changelog must fail rather than emit an appcast with empty notes.
if (
  cd "$TMP/project"
  "$ROOT/scripts/generate-appcast.sh" 9.9.9 dist/WinMice-9.9.9.zip docs/nope.md
) >/dev/null 2>&1; then
  echo "expected generate-appcast to fail on a missing changelog" >&2
  exit 1
fi

printf 'generate-appcast test passed\n'
