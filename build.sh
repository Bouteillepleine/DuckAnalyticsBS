#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
SRC=duckanalyticsbs
VER=$(sed -n 's/^version=v//p' "$SRC/module.prop")
OUT=DuckAnalyticsBS-v$VER.zip

FILES=(
  module.prop
  customize.sh
  common.sh
  ctl.sh
  action.sh
  service.sh
  post-fs-data.sh
  uninstall.sh
  webroot/index.html
  webroot/config.json
  webroot/icon.png
  META-INF/com/google/android/update-binary
  META-INF/com/google/android/updater-script
)

for f in "${FILES[@]}"; do
  [ -f "$SRC/$f" ] || { echo "missing: $SRC/$f" >&2; exit 1; }
done

for f in "${FILES[@]}"; do
  case "$f" in
    *.png) continue ;;
  esac
  if grep -qU $'\r' "$SRC/$f"; then
    echo "CRLF in $SRC/$f - refusing to package" >&2
    exit 1
  fi
done

for f in module.prop customize.sh common.sh ctl.sh action.sh service.sh post-fs-data.sh uninstall.sh; do
  case "$f" in
    *.sh)
      if ! dash -n "$SRC/$f" 2>/dev/null; then
        echo "not POSIX-clean: $SRC/$f" >&2
        dash -n "$SRC/$f" || true
        exit 1
      fi
      ;;
  esac
done

rm -f "$OUT"
( cd "$SRC" && zip -X -q "../$OUT" "${FILES[@]}" )
echo "built $OUT"
unzip -l "$OUT"
