#!/bin/sh
set -eu

# A release tag publishes a non-prerelease, and GitHub treats the newest
# non-prerelease as `latest`. Because SUFeedURL points at
# releases/latest/download/appcast.xml, whatever this accepts becomes the
# update feed for every installed copy. Only a plain three-component numeric
# version is allowed; release candidates belong on the workflow_dispatch path,
# which forces a prerelease.
VERSION="${1-}"

reject() {
  echo "invalid release version '$VERSION': $1" >&2
  echo "expected <major>.<minor>.<patch>, all numeric, no suffix" >&2
  exit 1
}

[ -n "$VERSION" ] || reject "empty"

case "$VERSION" in
  *[!0-9.]*) reject "contains something other than digits and dots" ;;
  *..*) reject "empty component" ;;
  .*) reject "leading dot" ;;
  *.) reject "trailing dot" ;;
esac

MAJOR="${VERSION%%.*}"
REST="${VERSION#*.}"
MINOR="${REST%%.*}"
PATCH="${REST#*.}"

[ "$MAJOR" != "$VERSION" ] || reject "not enough components"
[ "$MINOR" != "$REST" ] || reject "not enough components"
case "$PATCH" in
  *.*) reject "too many components" ;;
esac

exit 0
