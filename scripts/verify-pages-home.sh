#!/bin/sh
set -eu

ROOT="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
HTML="$ROOT/docs/index.html"
CSS="$ROOT/docs/styles.css"
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

need_file "$HTML"
need_file "$CSS"
need_file "$ROOT/docs/.nojekyll"
need_file "$ROOT/docs/icon.png"
need_file "$ROOT/docs/assets/hero-bg.jpg"
need_file "$ROOT/docs/assets/settings-scroll.jpg"
need_file "$ROOT/docs/assets/settings-nav.jpg"

need_contains "$HTML" 'Windows-style mouse on Mac'
need_contains "$HTML" 'https://anibalribeiro.cz/Winmice/'
need_contains "$HTML" 'https://github.com/anibalribeiro/WinMice/releases/latest'
need_contains "$HTML" 'brew tap anibalribeiro/winmice'
need_contains "$HTML" 'brew trust anibalribeiro/winmice'
need_contains "$HTML" 'brew install --cask winmice'
need_contains "$HTML" 'styles.css'
need_contains "$CSS" 'assets/hero-bg.jpg'
need_contains "$HTML" 'assets/settings-scroll.jpg'
need_contains "$HTML" 'assets/settings-nav.jpg'
need_contains "$HTML" 'id="demo-band"'
need_contains "$HTML" 'paypal.me/anibalccribeiro'
need_contains "$CSS" '--color-charcoal'
need_contains "$CSS" '--color-accent'
need_contains "$CSS" '#demo-band'

# Demo: either CSS mock class present, or a media file exists
if ! grep -F -q 'demo-mock' "$HTML"; then
  if [ ! -f "$ROOT/docs/assets/demo-loop.webm" ] && [ ! -f "$ROOT/docs/assets/demo-loop.gif" ]; then
    echo "need demo-mock in index.html or docs/assets/demo-loop.webm|gif"
    fail=1
  fi
fi

exit "$fail"
