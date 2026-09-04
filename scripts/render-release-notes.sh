#!/bin/sh
set -eu

VERSION="${1:?usage: render-release-notes.sh <version>}"
TEMPLATE="docs/release-notes-template.md"
CHANGELOG="docs/changelog/${VERSION}.md"

[ -f "$TEMPLATE" ] || { echo "missing $TEMPLATE" >&2; exit 1; }
# Failing here is deliberate: a release should not be publishable without notes.
[ -f "$CHANGELOG" ] || { echo "missing $CHANGELOG — write the changelog before tagging" >&2; exit 1; }

awk -v version="$VERSION" -v changelog="$CHANGELOG" '
  $0 == "{{CHANGES}}" {
    while ((getline line < changelog) > 0) print line
    close(changelog)
    next
  }
  {
    gsub(/\{\{VERSION\}\}/, version)
    print
  }
' "$TEMPLATE"
