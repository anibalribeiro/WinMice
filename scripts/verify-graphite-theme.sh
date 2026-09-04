#!/bin/sh
set -eu

ROOT="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
THEME="$ROOT/Sources/WinMice/Settings/WinMiceTheme.swift"
SETTINGS_VIEW="$ROOT/Sources/WinMice/Settings/SettingsView.swift"
fail=0

need_file() {
  [ -f "$1" ] || { echo "missing file: $1"; fail=1; }
}

need_contains() {
  file="$1"
  needle="$2"
  if [ ! -f "$file" ] || ! grep -F -q -- "$needle" "$file"; then
    echo "missing in $(echo "$file" | sed "s|^$ROOT/||"): $needle"
    fail=1
  fi
}

need_not_contain() {
  file="$1"
  needle="$2"
  if [ -f "$file" ] && grep -F -q -- "$needle" "$file"; then
    echo "unexpected in $(echo "$file" | sed "s|^$ROOT/||"): $needle"
    fail=1
  fi
}

need_file "$THEME"
need_contains "$THEME" 'enum WinMiceTheme'
need_contains "$THEME" '#7EB8FF'
need_contains "$THEME" '#1A1F26'
need_contains "$THEME" '#E8ECF1'
need_contains "$THEME" '#C5CED9'
need_contains "$THEME" '#9AA8B8'
need_contains "$THEME" 'sheetCornerRadius'
need_contains "$THEME" 'rowCornerRadius'

need_file "$SETTINGS_VIEW"
need_contains "$SETTINGS_VIEW" 'WinMiceTheme.accent'
need_contains "$SETTINGS_VIEW" 'sheetCornerRadius'
need_not_contain "$SETTINGS_VIEW" 'VisualEffectBackground(material: .sidebar)'

if [ "$fail" -ne 0 ]; then
  exit "$fail"
fi

cd "$ROOT"
swift build
