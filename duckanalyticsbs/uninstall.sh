#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh" 2>/dev/null

peach_redirect_del 2>/dev/null

if [ -s "$STATE" ] && [ "$(getprop sys.boot_completed)" = "1" ]; then
  revert_all
  if [ ! -s "$STATE" ]; then
    rm -f "$STATE" 2>/dev/null
    exit 0
  fi
fi

PENDING=/data/adb/$MODID.revert
HELPER=/data/adb/service.d/$MODID-revert.sh

[ -s "$STATE" ] || exit 0
cp -f "$STATE" "$PENDING" 2>/dev/null || exit 0
rm -f "$STATE" 2>/dev/null
mkdir -p /data/adb/service.d 2>/dev/null

cat > "$HELPER" <<'HELPEOF'
#!/system/bin/sh
MODID=duckanalyticsbs
PENDING=/data/adb/$MODID.revert
LOG=/data/adb/$MODID-revert.log
SELF=$0
G=com.google.android.gms

[ -s "$PENDING" ] || { rm -f "$SELF" "$PENDING"; exit 0; }

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 200 ]; do
  sleep 3
  i=$((i + 1))
done
[ "$(getprop sys.boot_completed)" = "1" ] || exit 0
sleep 20

while IFS=' ' read -r kind a b; do
  [ -n "$kind" ] || continue
  case "$kind" in
    comp)    pm enable --user 0 "$G/$a" >/dev/null 2>&1; echo "enabled $G/$a" >> "$LOG" ;;
    pkg)     pm enable --user 0 "$a" >/dev/null 2>&1; echo "enabled $a" >> "$LOG" ;;
    op)      [ -n "$b" ] || b=allow
             cmd appops set --uid "$G" "$a" "$b" >/dev/null 2>&1; echo "appop $a $b" >> "$LOG" ;;
    setting) settings put global "$a" "$b" 2>/dev/null; echo "setting $a=$b" >> "$LOG" ;;
    sysctl)  [ -w "/proc/sys/kernel/$a" ] && echo "$b" > "/proc/sys/kernel/$a" 2>/dev/null
             echo "sysctl $a=$b" >> "$LOG" ;;
  esac
done < "$PENDING"

echo "revert complete" >> "$LOG"
rm -f "$PENDING" "$SELF"
HELPEOF

chmod 0755 "$HELPER" 2>/dev/null
