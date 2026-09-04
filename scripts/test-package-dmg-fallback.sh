#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/project/dist/WinMice.app" "$TMP/project/docs/dmg"
printf 'background\n' > "$TMP/project/docs/dmg/background.png"
printf 'Install {{VERSION}}\n' > "$TMP/project/docs/dmg/INSTALL.txt"

cat > "$TMP/bin/ditto" <<'EOF'
#!/bin/sh
cp -R "$1" "$2"
EOF

cat > "$TMP/bin/create-dmg" <<'EOF'
#!/bin/sh
count=0
[ ! -f "$TEST_STATE/count" ] || count=$(cat "$TEST_STATE/count")
count=$((count + 1))
printf '%s\n' "$count" > "$TEST_STATE/count"
printf '%s\n' "$*" >> "$TEST_STATE/calls"

skip_jenkins=false
previous=
last=
for argument do
  [ "$argument" != "--skip-jenkins" ] || skip_jenkins=true
  previous=$last
  last=$argument
done

[ "$skip_jenkins" = true ] || exit 17
: > "$previous"
EOF

chmod +x "$TMP/bin/ditto" "$TMP/bin/create-dmg"
export TEST_STATE="$TMP"

if ! (
  cd "$TMP/project"
  PATH="$TMP/bin:$PATH" "$ROOT/scripts/package-dmg.sh" 1.2.3
) >"$TMP/stdout" 2>"$TMP/stderr"; then
  printf 'package-dmg fallback unexpectedly failed\n' >&2
  cat "$TMP/stderr" >&2
  exit 1
fi

[ "$(cat "$TMP/count")" = 2 ]
[ -f "$TMP/project/dist/WinMice-1.2.3.dmg" ]
grep -q -- '--skip-jenkins' "$TMP/calls"
grep -q 'WARNING:.*visual styling was skipped' "$TMP/stderr"

printf 'package-dmg fallback test passed\n'
