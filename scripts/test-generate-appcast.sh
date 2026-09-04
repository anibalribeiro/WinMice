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

# sign_update discovery must pick the EdDSA tool by name, not by find's
# traversal order, and must never fall back to the deprecated DSA script.
DISCOVERY_ROOT="$TMP/discovery"
mkdir -p "$DISCOVERY_ROOT/project/docs" "$DISCOVERY_ROOT/project/dist" "$DISCOVERY_ROOT/project/.build"
cp "$ROOT/docs/appcast-template.xml" "$DISCOVERY_ROOT/project/docs/appcast-template.xml"
printf 'zip contents\n' > "$DISCOVERY_ROOT/project/dist/WinMice-9.9.9.zip"
printf -- '- Discovery case.\n' > "$DISCOVERY_ROOT/project/docs/changelog-9.9.9.md"

mkdir -p "$DISCOVERY_ROOT/project/.build/artifacts/sparkle/Sparkle/bin/old_dsa_scripts"

cat > "$DISCOVERY_ROOT/project/.build/artifacts/sparkle/Sparkle/bin/sign_update" <<'EOF'
#!/bin/sh
printf 'correct-tool-ran\n' > "$TEST_STATE/discovery_marker"
printf 'sparkle:edSignature="ZGlzY292ZXJ5" length="99"\n'
EOF

cat > "$DISCOVERY_ROOT/project/.build/artifacts/sparkle/Sparkle/bin/old_dsa_scripts/sign_update" <<'EOF'
#!/bin/sh
printf 'dsa-tool-ran\n' > "$TEST_STATE/discovery_marker"
echo "old_dsa_scripts/sign_update takes positional args, not -f" >&2
exit 1
EOF

chmod +x "$DISCOVERY_ROOT/project/.build/artifacts/sparkle/Sparkle/bin/sign_update" \
         "$DISCOVERY_ROOT/project/.build/artifacts/sparkle/Sparkle/bin/old_dsa_scripts/sign_update"

if ! (
  cd "$DISCOVERY_ROOT/project"
  env -u SPARKLE_SIGN_UPDATE "$ROOT/scripts/generate-appcast.sh" 9.9.9 dist/WinMice-9.9.9.zip docs/changelog-9.9.9.md
) >"$TMP/discovery-stdout" 2>"$TMP/discovery-stderr"; then
  printf 'generate-appcast unexpectedly failed while discovering sign_update\n' >&2
  cat "$TMP/discovery-stderr" >&2
  exit 1
fi

grep -q 'correct-tool-ran' "$TMP/discovery_marker"
grep -q 'sparkle:edSignature="ZGlzY292ZXJ5"' "$DISCOVERY_ROOT/project/dist/appcast.xml"
rm -f "$TMP/discovery_marker"

# With no non-DSA sign_update present, discovery must fail loudly rather than
# silently falling back to the DSA script or proceeding with no tool at all.
ZERO_ROOT="$TMP/discovery-zero"
mkdir -p "$ZERO_ROOT/project/docs" "$ZERO_ROOT/project/dist" "$ZERO_ROOT/project/.build"
cp "$ROOT/docs/appcast-template.xml" "$ZERO_ROOT/project/docs/appcast-template.xml"
printf 'zip contents\n' > "$ZERO_ROOT/project/dist/WinMice-9.9.9.zip"
printf -- '- Zero-match case.\n' > "$ZERO_ROOT/project/docs/changelog-9.9.9.md"

mkdir -p "$ZERO_ROOT/project/.build/artifacts/sparkle/Sparkle/bin/old_dsa_scripts"
cat > "$ZERO_ROOT/project/.build/artifacts/sparkle/Sparkle/bin/old_dsa_scripts/sign_update" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$ZERO_ROOT/project/.build/artifacts/sparkle/Sparkle/bin/old_dsa_scripts/sign_update"

if (
  cd "$ZERO_ROOT/project"
  env -u SPARKLE_SIGN_UPDATE "$ROOT/scripts/generate-appcast.sh" 9.9.9 dist/WinMice-9.9.9.zip docs/changelog-9.9.9.md
) >"$TMP/zero-stdout" 2>"$TMP/zero-stderr"; then
  echo "expected generate-appcast to fail when no EdDSA sign_update is found" >&2
  exit 1
fi

grep -q 'expected exactly one sign_update under .build/artifacts, found 0' "$TMP/zero-stderr"

printf 'generate-appcast test passed\n'
