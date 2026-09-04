#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ORIG_PATH="$PATH"
ENTITLEMENTS="$(CDPATH= cd -- "$(dirname "$0")" && pwd)/WinMice.entitlements"

assert_codesign_arg_pair() {
  file="$1"
  opt="$2"
  val="$3"
  awk -v opt="$opt" -v val="$val" '
    { args[++n] = $0 }
    END {
      for (i = 1; i < n; i++) {
        if (args[i] == opt && args[i + 1] == val) {
          exit 0
        }
      }
      exit 1
    }
  ' "$file"
}

assert_codesign_arg_present() {
  file="$1"
  opt="$2"
  awk -v opt="$opt" '
    { args[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) {
        if (args[i] == opt) exit 0
      }
      exit 1
    }
  ' "$file"
}

# Ad-hoc path
unset CODESIGN_IDENTITY || true
./scripts/build-app.sh --version 0.0.0-test
codesign -dv --verbose=4 dist/WinMice.app 2>&1 | tee /tmp/winmice-adhoc-codesign.txt
grep -q 'Signature=adhoc' /tmp/winmice-adhoc-codesign.txt

# Release path must pass hardened-runtime + entitlements flags to codesign
RECORD_FILE="/tmp/winmice-release-codesign-args.txt"
rm -f "$RECORD_FILE"
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT HUP INT TERM
cat > "$STUB_DIR/codesign" <<STUB
#!/bin/sh
printf '@@INVOCATION@@\n' >> "$RECORD_FILE"
printf '%s\n' "\$@" >> "$RECORD_FILE"
exit 0
STUB
chmod +x "$STUB_DIR/codesign"
export CODESIGN_IDENTITY="Developer ID Application: Test Probe"
export PATH="$STUB_DIR:$ORIG_PATH"
./scripts/build-app.sh --version 0.0.0-test

if ! assert_codesign_arg_pair "$RECORD_FILE" --options runtime; then
  echo "release codesign missing --options runtime" >&2
  exit 1
fi
if ! assert_codesign_arg_pair "$RECORD_FILE" --entitlements "$ENTITLEMENTS"; then
  echo "release codesign missing --entitlements $ENTITLEMENTS" >&2
  exit 1
fi
if ! assert_codesign_arg_present "$RECORD_FILE" --timestamp; then
  echo "release codesign missing --timestamp" >&2
  exit 1
fi

# Sparkle's nested binaries must be signed separately from the app bundle, and
# only the app bundle may carry entitlements.
# `|| true` on every grep -c: a zero count makes grep exit 1, which under
# set -eu would kill the script before the explanatory message below.
INVOCATIONS=$(grep -c '@@INVOCATION@@' "$RECORD_FILE" || true)
if [ "$INVOCATIONS" -lt 2 ]; then
  echo "expected more than one codesign invocation (nested Sparkle signing missing), got $INVOCATIONS" >&2
  exit 1
fi
ENTITLEMENT_USES=$(grep -c -- '^--entitlements$' "$RECORD_FILE" || true)
if [ "$ENTITLEMENT_USES" -ne 1 ]; then
  echo "expected exactly one --entitlements use (the app bundle), got $ENTITLEMENT_USES" >&2
  exit 1
fi
if ! grep -q 'Sparkle.framework' "$RECORD_FILE"; then
  echo "expected Sparkle.framework to be signed explicitly" >&2
  exit 1
fi
# The app bundle must be signed last, so it seals the framework's hashes.
if [ "$(grep -v '^@@INVOCATION@@$' "$RECORD_FILE" | tail -n 1)" != "dist/WinMice.app" ]; then
  echo "expected dist/WinMice.app to be the last thing signed" >&2
  exit 1
fi

# Release path without a real identity must fail clearly (not silently ad-hoc)
export CODESIGN_IDENTITY="Developer ID Application: Not A Real Identity"
export PATH="$ORIG_PATH"
if ./scripts/build-app.sh --version 0.0.0-test; then
  echo "expected codesign to fail with fake identity" >&2
  exit 1
fi

# WINMICE_REQUIRE_DEVELOPER_ID=1 with no identity must fail closed, never
# silently fall back to an ad-hoc signed release build (see I3).
unset CODESIGN_IDENTITY || true
export WINMICE_REQUIRE_DEVELOPER_ID=1
if ./scripts/build-app.sh --version 0.0.0-test; then
  echo "expected build to fail when WINMICE_REQUIRE_DEVELOPER_ID=1 and CODESIGN_IDENTITY is empty" >&2
  exit 1
fi
unset WINMICE_REQUIRE_DEVELOPER_ID

echo "build-app signing modes OK"
