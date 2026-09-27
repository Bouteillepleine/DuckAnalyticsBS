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

NODE=""
for c in node /mnt/c/Program\ Files/nodejs/node.exe; do
  command -v "$c" >/dev/null 2>&1 && { NODE=$c; break; }
  [ -x "$c" ] && { NODE=$c; break; }
done
if [ -n "$NODE" ]; then
  TMPJS=$(mktemp -t dabs.XXXXXX.js)
  sed -n '/^<script>$/,/^<\/script>$/p' "$SRC/webroot/index.html" | sed '1d;$d' > "$TMPJS"
  [ -s "$TMPJS" ] || { echo "could not extract webroot JS" >&2; exit 1; }
  if ! "$NODE" --check "$(wslpath -w "$TMPJS" 2>/dev/null || echo "$TMPJS")" 2>&1; then
    echo "webroot/index.html JS does not parse - refusing to package" >&2
    rm -f "$TMPJS"
    exit 1
  fi
  rm -f "$TMPJS"
  echo "webroot JS parses"
else
  echo "warning: node not found, skipping JS syntax gate" >&2
fi

rm -f "$OUT"
( cd "$SRC" && zip -X -q "../$OUT" "${FILES[@]}" )
echo "built $OUT"
unzip -l "$OUT"
