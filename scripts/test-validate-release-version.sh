#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
VALIDATE="$ROOT/scripts/validate-release-version.sh"

fail=0

expect_ok() {
  if ! "$VALIDATE" "$1" >/dev/null 2>&1; then
    echo "expected '$1' to be accepted" >&2
    fail=1
  fi
}

expect_rejected() {
  if "$VALIDATE" "$1" >/dev/null 2>&1; then
    echo "expected '$1' to be rejected" >&2
    fail=1
  fi
}

expect_ok 1.0.0
expect_ok 1.1.0
expect_ok 0.0.1
expect_ok 10.20.30
expect_ok 1.10.0

# A release candidate must never take the tag-push path: that path publishes a
# non-prerelease, which becomes `latest`, which becomes the appcast feed every
# installed copy reads.
expect_rejected 1.2.0-rc1
expect_rejected 1.2.0-beta.3
expect_rejected 0.0.0-notarize-dry-run

# Wrong shape.
expect_rejected 1.2
expect_rejected 1.2.3.4
expect_rejected 1..3
expect_rejected .1.2
expect_rejected 1.2.
expect_rejected ""

# The caller strips the leading v; a version that still carries one means the
# caller is broken and the release must stop.
expect_rejected v1.2.3

# Nothing that could reach a filename, a tag, or a plist unescaped.
expect_rejected "1.2.3 "
expect_rejected "1.2/3"
expect_rejected '1.2.3; rm -rf /'
expect_rejected "1.a.3"

if [ "$fail" -ne 0 ]; then
  echo "validate-release-version test failed" >&2
  exit 1
fi

printf 'validate-release-version test passed\n'
