#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
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
  "$ROOT/scripts/generate-appcast.sh" 9.9.9 dist/WinMice-9.9.9.zip docs/changelog-9.9.9.md v9.9.9
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
  "$ROOT/scripts/generate-appcast.sh" 9.9.9 dist/WinMice-9.9.9.zip docs/nope.md v9.9.9
) >/dev/null 2>&1; then
  echo "expected generate-appcast to fail on a missing changelog" >&2
  exit 1
fi

# The download URL must come from the tag the release is actually published
# under, not from the version. A workflow_dispatch run tags manual-<version>,
# and an appcast pointing at v<version> would send every user to a 404.
if ! (
  cd "$TMP/project"
  "$ROOT/scripts/generate-appcast.sh" 9.9.9 dist/WinMice-9.9.9.zip docs/changelog-9.9.9.md manual-9.9.9
) >/dev/null 2>"$TMP/tag-stderr"; then
  printf 'generate-appcast failed for a manual- tag\n' >&2
  cat "$TMP/tag-stderr" >&2
  exit 1
fi

grep -q 'releases/download/manual-9.9.9/WinMice-9.9.9.zip' "$OUT"
if grep -q 'releases/download/v9.9.9/' "$OUT"; then
  echo "enclosure URL ignored the tag and used the version instead" >&2
  exit 1
fi

# The tag must be supplied explicitly. Defaulting it to v<version> is what
# allowed the mismatch in the first place, so absence is an error.
if (
  cd "$TMP/project"
  "$ROOT/scripts/generate-appcast.sh" 9.9.9 dist/WinMice-9.9.9.zip docs/changelog-9.9.9.md
) >/dev/null 2>&1; then
  echo "expected generate-appcast to require an explicit tag" >&2
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
  env -u SPARKLE_SIGN_UPDATE "$ROOT/scripts/generate-appcast.sh" 9.9.9 dist/WinMice-9.9.9.zip docs/changelog-9.9.9.md v9.9.9
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
  env -u SPARKLE_SIGN_UPDATE "$ROOT/scripts/generate-appcast.sh" 9.9.9 dist/WinMice-9.9.9.zip docs/changelog-9.9.9.md v9.9.9
) >"$TMP/zero-stdout" 2>"$TMP/zero-stderr"; then
  echo "expected generate-appcast to fail when no EdDSA sign_update is found" >&2
  exit 1
fi

grep -q 'expected exactly one sign_update under .build/artifacts, found 0' "$TMP/zero-stderr"

# A changelog is markdown written by hand, so it can legitimately contain XML
# metacharacters. `]]>` is the dangerous one: it closes the appcast's CDATA
# section early and produces invalid XML that Sparkle cannot parse. A broken
# appcast is the feed every installed copy reads, so this must fail the release
# rather than publish.
HOSTILE_ROOT="$TMP/hostile"
mkdir -p "$HOSTILE_ROOT/project/docs" "$HOSTILE_ROOT/project/dist"
cp "$ROOT/docs/appcast-template.xml" "$HOSTILE_ROOT/project/docs/appcast-template.xml"
printf 'zip contents\n' > "$HOSTILE_ROOT/project/dist/WinMice-9.9.9.zip"
{
  printf -- '- Fixed the `a[i]]>b` comparison.\n'
  printf -- '- Escaped & and < and > correctly.\n'
} > "$HOSTILE_ROOT/project/docs/changelog-9.9.9.md"

if ! (
  cd "$HOSTILE_ROOT/project"
  "$ROOT/scripts/generate-appcast.sh" 9.9.9 dist/WinMice-9.9.9.zip docs/changelog-9.9.9.md v9.9.9
) >"$TMP/hostile-stdout" 2>"$TMP/hostile-stderr"; then
  printf 'generate-appcast failed on a changelog containing XML metacharacters\n' >&2
  cat "$TMP/hostile-stderr" >&2
  exit 1
fi

HOSTILE_OUT="$HOSTILE_ROOT/project/dist/appcast.xml"
xmllint --noout "$HOSTILE_OUT" || {
  echo "a changelog containing ]]> produced invalid XML" >&2
  exit 1
}
# The text must survive the escaping, not be dropped or mangled.
xmllint --xpath 'string(/rss/channel/item/description)' "$HOSTILE_OUT" \
  | grep -q 'a\[i\]\]>b' || {
  echo "the ]]> escape lost or corrupted the changelog text" >&2
  exit 1
}

# An empty changelog would ship an update dialog with a blank "what's new"
# panel and equally blank release notes. `-f` accepts an empty file, so the
# check has to be `-s`.
: > "$HOSTILE_ROOT/project/docs/empty.md"
if (
  cd "$HOSTILE_ROOT/project"
  "$ROOT/scripts/generate-appcast.sh" 9.9.9 dist/WinMice-9.9.9.zip docs/empty.md v9.9.9
) >/dev/null 2>&1; then
  echo "expected generate-appcast to fail on an empty changelog" >&2
  exit 1
fi

# A template that would emit malformed XML must be caught even when every
# placeholder was substituted, because the placeholder guard cannot see it.
BADTPL_ROOT="$TMP/badtemplate"
mkdir -p "$BADTPL_ROOT/project/docs" "$BADTPL_ROOT/project/dist"
printf 'zip contents\n' > "$BADTPL_ROOT/project/dist/WinMice-9.9.9.zip"
printf -- '- A change.\n' > "$BADTPL_ROOT/project/docs/changelog-9.9.9.md"
printf '<?xml version="1.0"?>\n<rss><channel><item>{{VERSION}}</item></rss>\n' \
  > "$BADTPL_ROOT/project/docs/appcast-template.xml"
if (
  cd "$BADTPL_ROOT/project"
  "$ROOT/scripts/generate-appcast.sh" 9.9.9 dist/WinMice-9.9.9.zip docs/changelog-9.9.9.md v9.9.9
) >/dev/null 2>"$TMP/badtpl-stderr"; then
  echo "expected generate-appcast to reject a malformed appcast" >&2
  exit 1
fi
grep -q 'not well-formed XML' "$TMP/badtpl-stderr"

printf 'generate-appcast test passed\n'
