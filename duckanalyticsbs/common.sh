#!/system/bin/sh

MODID=duckanalyticsbs
MODDIR=${MODDIR:-/data/adb/modules/$MODID}
PROP=$MODDIR/module.prop
LOG=/data/adb/$MODID.log
STATE=/data/adb/$MODID.state
CACHE=/data/adb/$MODID.comps
CACHEVER=/data/adb/$MODID.compsver
CONF=/data/adb/$MODID.conf
LEGACY=/data/adb/modules/peach_roamstats_quiet

GMS=com.google.android.gms

VPATH=/vendor/etc/wifi/peach_v2/WCNSS_qcom_cfg.ini
TREE=$MODDIR/vendor/etc/wifi/peach_v2/WCNSS_qcom_cfg.ini
KEY=groam_info_stats_num

HT_PATH=/proc/sys/kernel/hung_task_timeout_secs
HT_TIMEOUT=300

NMBASE=/data/adb/modules/meta-nomount
ABI=$(getprop ro.product.cpu.abi 2>/dev/null)
NOMOUNT=$NMBASE/bin/$ABI/nomount
export NM_BIN=$NMBASE/bin/$ABI/nm

GMS_TEL="
.analytics.AnalyticsReceiver
.analytics.AnalyticsTaskService
.analytics.service.AnalyticsService
.common.stats.GmsCoreStatsService
.stats.PlatformStatsCollectorService
.stats.service.DropBoxEntryAddedReceiver
.stats.service.DropBoxEntryAddedService
.clearcut.uploader.QosUploaderService
.measurement.PackageMeasurementReceiver
.measurement.PackageMeasurementTaskService
.usagereporting.service.UsageReportingIntentService
"

GMS_LOC="
com.google.android.location.reporting.service.UploadGcmTaskService
com.google.android.location.reporting.service.DispatchingService
com.google.android.location.reporting.service.ReportingSyncService
.semanticlocationhistory.deidentifieddata.uploads.BatchDeidentifiedDataUploadService
.locationsharingreporter.service.reporting.periodic.PeriodicReporterMonitoringService
"

GMS_ACT_OPS="ACTIVITY_RECOGNITION BODY_SENSORS"

OOS_TEL="
com.oplus.statistics.rom
com.oplus.olc
com.oplus.logkit
com.oplus.metis
com.oplus.stdid
com.oplus.nhs
"

feat_peach=1
feat_hungtask=1
feat_gmstel=1
feat_oostel=1
feat_gmsloc=0
feat_gmsact=0
feat_wifiscan=0

[ -f "$CONF" ] && . "$CONF"

[ -s "$STATE" ] || { [ -s "$MODDIR/state" ] && cp -f "$MODDIR/state" "$STATE" 2>/dev/null; }

log() {
  printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null
  if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 600 ]; then
    tail -300 "$LOG" > "$LOG.t" 2>/dev/null && mv -f "$LOG.t" "$LOG" 2>/dev/null
  fi
}

conf_set() {
  [ -f "$CONF" ] || : > "$CONF"
  if grep -q "^$1=" "$CONF" 2>/dev/null; then
    sed -i "s|^$1=.*|$1=$2|" "$CONF"
  else
    printf '%s=%s\n' "$1" "$2" >> "$CONF"
  fi
}

state_add() {
  [ -f "$STATE" ] && grep -qxF "$1" "$STATE" && return 0
  printf '%s\n' "$1" >> "$STATE"
}

state_del() {
  [ -f "$STATE" ] || return 0
  grep -vxF "$1" "$STATE" > "$STATE.t" 2>/dev/null
  mv -f "$STATE.t" "$STATE" 2>/dev/null
}

state_has() { [ -f "$STATE" ] && grep -qxF "$1" "$STATE"; }

full_comp() {
  case "$1" in
    .*) printf '%s%s\n' "$GMS" "$1" ;;
    *)  printf '%s\n' "$1" ;;
  esac
}

set_full() {
  case "$1" in
    .*) FULL=$GMS$1 ;;
    *)  FULL=$1 ;;
  esac
}

gms_version() { dumpsys package "$GMS" 2>/dev/null | grep -m1 'versionName=' | tr -d ' '; }

cache_drop() { rm -f "$CACHE" "$CACHEVER" 2>/dev/null; }

build_cache() {
  v=$(gms_version)
  [ -n "$v" ] || return 1
  [ -s "$CACHE" ] && [ "$v" = "$(cat "$CACHEVER" 2>/dev/null)" ] && return 0
  t=/data/local/tmp/.$MODID.dump
  pm dump "$GMS" > "$t" 2>/dev/null
  [ -s "$t" ] || { rm -f "$t"; return 1; }
  grep -oE "$GMS/[a-zA-Z0-9_.$]+" "$t" | sort -u | while IFS= read -r c; do
    full_comp "${c#$GMS/}"
  done > "$CACHE"
  rm -f "$t"
  [ -s "$CACHE" ] || return 1
  printf '%s\n' "$v" > "$CACHEVER"
  log "component cache built for $v ($(wc -l < "$CACHE") entries)"
  return 0
}

comp_exists() { set_full "$1"; [ -s "$CACHE" ] && grep -qxF "$FULL" "$CACHE"; }

DIS=/data/local/tmp/.$MODID.dis
PKGS=/data/local/tmp/.$MODID.pkgs
PKGSD=/data/local/tmp/.$MODID.pkgsd
LOOKUP_TTL=12

_dis_ok=0
_pkgs_ok=0

fresh() {
  [ -s "$1" ] || return 1
  _f_now=$(date +%s 2>/dev/null) || return 1
  _f_mt=$(stat -c %Y "$1" 2>/dev/null) || return 1
  [ -n "$_f_now" ] && [ -n "$_f_mt" ] || return 1
  [ "$((_f_now - _f_mt))" -lt "$LOOKUP_TTL" ] && [ "$((_f_now - _f_mt))" -ge 0 ]
}

dis_refresh() {
  dumpsys package "$GMS" 2>/dev/null | sed -n '/disabledComponents:/,/enabledComponents:/p' > "$DIS" 2>/dev/null
  _dis_ok=1
}

pkgs_refresh() {
  pm list packages --user 0 > "$PKGS" 2>/dev/null
  pm list packages -d --user 0 > "$PKGSD" 2>/dev/null
  _pkgs_ok=1
}

comp_disabled() {
  [ "$_dis_ok" = 1 ] || { fresh "$DIS" || dis_refresh; _dis_ok=1; }
  set_full "$1"
  grep -qF "$FULL" "$DIS" 2>/dev/null
}

pkg_present() {
  [ "$_pkgs_ok" = 1 ] || { fresh "$PKGS" || pkgs_refresh; _pkgs_ok=1; }
  grep -qx "package:$1" "$PKGS" 2>/dev/null
}

pkg_disabled() {
  [ "$_pkgs_ok" = 1 ] || { fresh "$PKGSD" || pkgs_refresh; _pkgs_ok=1; }
  grep -qx "package:$1" "$PKGSD" 2>/dev/null
}

op_is() { cmd appops get --uid "$GMS" "$1" 2>/dev/null | grep -q "Uid mode: $1: $2"; }

comp_apply() {
  c=$(full_comp "$1")
  if comp_disabled "$1"; then
    state_has "comp $c" || log "pre-disabled elsewhere, will not re-enable on uninstall: $c"
    return 0
  fi
  comp_exists "$1" || { log "skip absent component $c"; return 1; }
  out=$(pm disable --user 0 "$GMS/$c" 2>&1)
  dis_refresh
  if comp_disabled "$1"; then
    state_add "comp $c"
    log "disabled component $c"
    return 0
  fi
  case "$out" in
    *"does not exist"*)
      log "absent: $c is listed by pm dump but PackageManager rejects it"
      return 1
      ;;
  esac
  log "FAILED to disable component $c"
  return 1
}

comp_revert() {
  c=$(full_comp "$1")
  state_has "comp $c" || return 0
  pm enable --user 0 "$GMS/$c" >/dev/null 2>&1
  dis_refresh
  if comp_disabled "$1"; then
    log "FAILED to re-enable component $c"
    return 1
  fi
  state_del "comp $c"
  log "re-enabled component $c"
}

pkg_apply() {
  if pkg_disabled "$1"; then
    state_has "pkg $1" || log "pre-disabled elsewhere, will not re-enable on uninstall: $1"
    return 0
  fi
  pkg_present "$1" || { log "skip absent package $1"; return 1; }
  pm disable --user 0 "$1" >/dev/null 2>&1
  pkgs_refresh
  if pkg_disabled "$1"; then
    state_add "pkg $1"
    log "disabled package $1"
    return 0
  fi
  log "FAILED to disable package $1"
  return 1
}

pkg_revert() {
  state_has "pkg $1" || return 0
  pm enable --user 0 "$1" >/dev/null 2>&1
  pkgs_refresh
  if pkg_disabled "$1"; then
    log "FAILED to re-enable package $1"
    return 1
  fi
  state_del "pkg $1"
  log "re-enabled package $1"
}

op_state_line() { grep -m1 "^op $1 " "$STATE" 2>/dev/null; }

op_mode() {
  cmd appops get --uid "$GMS" "$1" 2>/dev/null | sed -n "s/^Uid mode: $1: \([a-z]*\).*/\1/p" | head -1
}

op_apply() {
  if op_is "$1" ignore; then
    [ -n "$(op_state_line "$1")" ] || log "pre-set elsewhere, will not restore on uninstall: appop $1"
    return 0
  fi
  orig=$(op_mode "$1")
  [ -n "$orig" ] || orig=allow
  cmd appops set --uid "$GMS" "$1" ignore >/dev/null 2>&1
  if op_is "$1" ignore; then
    state_add "op $1 $orig"
    log "appop $1 $orig -> ignore"
    return 0
  fi
  log "FAILED to set appop $1"
  return 1
}

op_revert() {
  line=$(op_state_line "$1")
  [ -n "$line" ] || return 0
  orig=$(printf '%s' "$line" | awk '{print $3}')
  [ -n "$orig" ] || orig=allow
  cmd appops set --uid "$GMS" "$1" "$orig" >/dev/null 2>&1
  state_del "$line"
  log "appop $1 -> $orig"
}

count_comp_applied() {
  n=0
  for c in $1; do comp_disabled "$c" && n=$((n + 1)); done
  echo "$n"
}

count_comp_present() {
  n=0
  for c in $1; do
    if comp_exists "$c" || comp_disabled "$c"; then n=$((n + 1)); fi
  done
  echo "$n"
}

count_pkg_applied() {
  n=0
  for p in $OOS_TEL; do pkg_disabled "$p" && n=$((n + 1)); done
  echo "$n"
}

count_pkg_present() {
  n=0
  for p in $OOS_TEL; do pkg_present "$p" && n=$((n + 1)); done
  echo "$n"
}

count_op_applied() {
  n=0
  for o in $GMS_ACT_OPS; do op_is "$o" ignore && n=$((n + 1)); done
  echo "$n"
}

gmstel_apply()  { for c in $GMS_TEL; do comp_apply  "$c"; done; }
gmstel_revert() { for c in $GMS_TEL; do comp_revert "$c"; done; }
gmsloc_apply()  { for c in $GMS_LOC; do comp_apply  "$c"; done; }
gmsloc_revert() { for c in $GMS_LOC; do comp_revert "$c"; done; }
gmsact_apply()  { for o in $GMS_ACT_OPS; do op_apply  "$o"; done; }
gmsact_revert() { for o in $GMS_ACT_OPS; do op_revert "$o"; done; }
oostel_apply()  { for p in $OOS_TEL; do pkg_apply  "$p"; done; }
oostel_revert() { for p in $OOS_TEL; do pkg_revert "$p"; done; }

wifiscan_get() { settings get global wifi_scan_always_enabled 2>/dev/null; }

wifiscan_apply() {
  cur=$(wifiscan_get)
  [ "$cur" = "0" ] && return 0
  state_add "setting wifi_scan_always_enabled $cur"
  settings put global wifi_scan_always_enabled 0 2>/dev/null
  log "wifi_scan_always_enabled $cur -> 0"
}

wifiscan_revert() {
  old=$(grep -m1 '^setting wifi_scan_always_enabled ' "$STATE" 2>/dev/null | awk '{print $3}')
  [ -n "$old" ] || return 0
  settings put global wifi_scan_always_enabled "$old" 2>/dev/null
  state_del "setting wifi_scan_always_enabled $old"
  log "wifi_scan_always_enabled -> $old"
}

sysctl_apply() {
  [ -w "$HT_PATH" ] || return 0
  cur=$(cat "$HT_PATH" 2>/dev/null)
  [ "$cur" = "$HT_TIMEOUT" ] && return 0
  grep -q '^sysctl hung_task_timeout_secs ' "$STATE" 2>/dev/null || \
    state_add "sysctl hung_task_timeout_secs $cur"
  echo "$HT_TIMEOUT" > "$HT_PATH" 2>/dev/null
  log "hung_task_timeout_secs $cur -> $HT_TIMEOUT"
}

sysctl_revert() {
  old=$(grep -m1 '^sysctl hung_task_timeout_secs ' "$STATE" 2>/dev/null | awk '{print $3}')
  [ -n "$old" ] || return 0
  [ -w "$HT_PATH" ] && echo "$old" > "$HT_PATH" 2>/dev/null
  state_del "sysctl hung_task_timeout_secs $old"
  log "hung_task_timeout_secs -> $old"
}

have_suite() { [ -x "$NOMOUNT" ] && [ -x "$NM_BIN" ]; }
is_peach() { [ -f "$VPATH" ]; }

key_ok() {
  [ -f "$1" ] || return 1
  grep -q "^$KEY=0" "$1" || return 1
  if grep -q '^END' "$1"; then
    k=$(grep -n "^$KEY=0" "$1" | head -1 | cut -d: -f1)
    e=$(grep -n '^END' "$1" | head -1 | cut -d: -f1)
    [ -n "$k" ] && [ -n "$e" ] && [ "$k" -lt "$e" ] || return 1
  fi
  return 0
}

peach_on() { key_ok "$TREE"; }
peach_active() { have_suite && "$NM_BIN" list 2>/dev/null | grep -q "^$VPATH -> "; }

peach_write_patched() {
  src=$1
  dst=$2
  tmp=$dst.new
  ins=0
  : > "$tmp" 2>/dev/null || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$KEY"=*) continue ;;
      END)
        if [ "$ins" = 0 ]; then
          printf '%s=0\n\n' "$KEY" >> "$tmp"
          ins=1
        fi
        ;;
    esac
    printf '%s\n' "$line" >> "$tmp"
  done < "$src"
  if [ "$ins" = 0 ]; then
    rm -f "$tmp" 2>/dev/null
    return 1
  fi
  mv -f "$tmp" "$dst" 2>/dev/null
}

peach_generate() {
  [ -n "$KEY" ] || { log "generate: KEY unset"; return 1; }
  have_suite && "$NOMOUNT" vfs del "$VPATH" >/dev/null 2>&1
  [ -s "$VPATH" ] || { log "generate: stock INI missing or empty at $VPATH"; return 1; }
  grep -q '^END' "$VPATH" || { log "generate: stock INI has no END marker, refusing to patch"; return 1; }
  mkdir -p "${TREE%/*}" || { log "generate: cannot create ${TREE%/*}"; return 1; }
  peach_write_patched "$VPATH" "$TREE" || { log "generate: could not write patched INI"; return 1; }
  if ! key_ok "$TREE"; then
    log "generate: patched file failed verification, discarding"
    rm -f "$TREE" 2>/dev/null
    return 1
  fi
  chmod 0644 "$TREE" 2>/dev/null
  log "generate: patched INI written to $TREE"
  return 0
}

peach_redirect_add() { have_suite && "$NOMOUNT" vfs add "$VPATH" "$TREE" 2>/dev/null; }
peach_redirect_del() { have_suite && "$NOMOUNT" vfs del "$VPATH" 2>/dev/null; }

reload_wifi() {
  command -v svc >/dev/null 2>&1 || return 0
  if [ "$(settings get global wifi_on 2>/dev/null)" = "1" ]; then
    log "cycling Wi-Fi to reload driver INI"
    svc wifi disable 2>/dev/null
    sleep 3
    svc wifi enable 2>/dev/null
  else
    log "Wi-Fi off; INI applies when Wi-Fi is next enabled"
  fi
}

flood_total() { dmesg 2>/dev/null | grep -c extract_roam_trigger_stats_tlv; }

recent_flood() {
  _rf_now=$(cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1)
  [ -n "$_rf_now" ] || return 1
  _rf_n=$(dmesg 2>/dev/null | grep extract_roam_trigger_stats_tlv | awk -v t="$(( _rf_now - 30 ))" '{ if (match($0, /^\[ *[0-9]+/)) { s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); if (s + 0 > t) c++ } } END { print c + 0 }')
  [ "${_rf_n:-0}" -gt 0 ]
}

peach_turn_on() { peach_generate || return 1; peach_redirect_add; reload_wifi; }
peach_turn_off() { peach_redirect_del; rm -f "$TREE" 2>/dev/null; reload_wifi; }

apply_all() {
  build_cache || log "component cache unavailable; component features skipped this pass"
  [ "$feat_hungtask" = "1" ] && sysctl_apply
  [ "$feat_gmstel" = "1" ] && gmstel_apply
  [ "$feat_oostel" = "1" ] && oostel_apply
  [ "$feat_gmsloc" = "1" ] && gmsloc_apply
  [ "$feat_gmsact" = "1" ] && gmsact_apply
  [ "$feat_wifiscan" = "1" ] && wifiscan_apply
  return 0
}

revert_all() {
  gmstel_revert
  gmsloc_revert
  oostel_revert
  gmsact_revert
  wifiscan_revert
  sysctl_revert
  peach_redirect_del
  return 0
}

feat_on() {
  case "$1" in
    peach)    conf_set feat_peach 1;    feat_peach=1;    is_peach && peach_turn_on ;;
    gmstel)   conf_set feat_gmstel 1;   feat_gmstel=1;   build_cache; gmstel_apply ;;
    oostel)   conf_set feat_oostel 1;   feat_oostel=1;   oostel_apply ;;
    gmsloc)   conf_set feat_gmsloc 1;   feat_gmsloc=1;   build_cache; gmsloc_apply ;;
    gmsact)   conf_set feat_gmsact 1;   feat_gmsact=1;   gmsact_apply ;;
    wifiscan) conf_set feat_wifiscan 1; feat_wifiscan=1; wifiscan_apply ;;
    hungtask) conf_set feat_hungtask 1; feat_hungtask=1; sysctl_apply ;;
    all)      for f in peach gmstel oostel hungtask; do feat_on "$f"; done ;;
    *)        echo "unknown feature: $1"; return 1 ;;
  esac
}

feat_off() {
  case "$1" in
    peach)    conf_set feat_peach 0;    feat_peach=0;    peach_turn_off ;;
    gmstel)   conf_set feat_gmstel 0;   feat_gmstel=0;   gmstel_revert ;;
    oostel)   conf_set feat_oostel 0;   feat_oostel=0;   oostel_revert ;;
    gmsloc)   conf_set feat_gmsloc 0;   feat_gmsloc=0;   gmsloc_revert ;;
    gmsact)   conf_set feat_gmsact 0;   feat_gmsact=0;   gmsact_revert ;;
    wifiscan) conf_set feat_wifiscan 0; feat_wifiscan=0; wifiscan_revert ;;
    hungtask) conf_set feat_hungtask 0; feat_hungtask=0; sysctl_revert ;;
    all)      revert_all ;;
    *)        echo "unknown feature: $1"; return 1 ;;
  esac
}

card_text() {
  gp=$(count_comp_present "$GMS_TEL"); ga=$(count_comp_applied "$GMS_TEL")
  op=$(count_pkg_present); oa=$(count_pkg_applied)
  if [ "$ga" = "$gp" ]; then g="GMS $ga"; else g="GMS $ga/$gp"; fi
  if [ "$oa" = "$op" ]; then o="OOS $oa"; else o="OOS $oa/$op"; fi
  x=""
  [ "$feat_gmsloc" = "1" ] && x="$x · loc $(count_comp_applied "$GMS_LOC")"
  [ "$feat_gmsact" = "1" ] && x="$x · sensors $(count_op_applied)"
  [ "$feat_wifiscan" = "1" ] && [ "$(wifiscan_get)" = "0" ] && x="$x · wifiscan off"
  if is_peach; then
    if peach_on && peach_active; then x="$x · dmesg quiet"
    elif peach_on; then x="$x · dmesg staged"
    else x="$x · dmesg loud"; fi
  fi
  if [ "$ga" = "0" ] && [ "$oa" = "0" ]; then
    printf '🔴 off%s\n' "$x"
  elif [ "$ga" = "$gp" ] && [ "$oa" = "$op" ]; then
    printf '🟢 %s · %s%s\n' "$g" "$o" "$x"
  else
    printf '🟡 %s · %s%s\n' "$g" "$o" "$x"
  fi
}

set_card() {
  txt=$(card_text)
  esc=$(printf '%s' "$txt" | sed 's/|/\\|/g')
  [ -f "$PROP" ] && sed -i "s|^description=.*|description=$esc|" "$PROP"
  if [ "$1" = "live" ] && command -v ksud >/dev/null 2>&1; then
    KSU_MODULE="$MODID" ksud module config set --temp override.description "$txt" >/dev/null 2>&1
  fi
}

jbool() { if [ "$1" = "1" ]; then echo true; else echo false; fi; }

status_json() {
  build_cache >/dev/null 2>&1
  pd=false; po=false; pa=false
  is_peach && pd=true
  peach_on && po=true
  peach_active && pa=true
  ht=$(cat "$HT_PATH" 2>/dev/null)
  printf '{'
  printf '"peach":{"dev":%s,"on":%s,"active":%s,"want":%s,"flood":%s},' \
    "$pd" "$po" "$pa" "$(jbool "$feat_peach")" "$(flood_total)"
  printf '"gmstel":{"want":%s,"applied":%s,"present":%s},' \
    "$(jbool "$feat_gmstel")" "$(count_comp_applied "$GMS_TEL")" "$(count_comp_present "$GMS_TEL")"
  printf '"oostel":{"want":%s,"applied":%s,"present":%s},' \
    "$(jbool "$feat_oostel")" "$(count_pkg_applied)" "$(count_pkg_present)"
  printf '"gmsloc":{"want":%s,"applied":%s,"present":%s},' \
    "$(jbool "$feat_gmsloc")" "$(count_comp_applied "$GMS_LOC")" "$(count_comp_present "$GMS_LOC")"
  printf '"gmsact":{"want":%s,"applied":%s,"present":2},' \
    "$(jbool "$feat_gmsact")" "$(count_op_applied)"
  printf '"wifiscan":{"want":%s,"value":"%s"},' "$(jbool "$feat_wifiscan")" "$(wifiscan_get)"
  printf '"hungtask":{"want":%s,"value":%s}' "$(jbool "$feat_hungtask")" "${ht:-0}"
  printf '}\n'
}

gms_uid() { pm list packages -U 2>/dev/null | grep "package:$GMS " | awk -F'uid:' '{print $2}'; }

measure() {
  u=$(gms_uid)
  echo "-- GMS wakelocks since last charge (uid $u)"
  dumpsys batterystats --charged 2>/dev/null | grep "Wake lock u0a$(( ${u:-10000} - 10000 ))" | head -6
  echo
  echo "-- GMS BLE scan clients (untouched by design)"
  dumpsys bluetooth_manager 2>/dev/null | grep -F "appName: $GMS" | head -4
}

report() {
  build_cache >/dev/null 2>&1
  echo "== DuckAnalyticsBS =="
  echo "GMS $(gms_version)"
  echo
  echo "-- peach_v2 roam-stats (dmesg)"
  printf '   %-22s %s\n' "peach INI on device" "$(is_peach && echo yes || echo no)"
  printf '   %-22s %s\n' "backing file patched" "$(peach_on && echo yes || echo no)"
  printf '   %-22s %s\n' "redirect live" "$(peach_active && echo yes || echo no)"
  printf '   %-22s %s\n' "flood lines in dmesg" "$(flood_total)"
  printf '   %-22s %s\n' "hung_task_timeout" "$(cat "$HT_PATH" 2>/dev/null)"
  echo
  echo "-- GMS telemetry components"
  for c in $GMS_TEL; do
    if ! comp_exists "$c"; then s=absent
    elif comp_disabled "$c"; then s=disabled
    else s=ENABLED; fi
    printf '   %-9s %s\n' "$s" "$c"
  done
  echo
  echo "-- OxygenOS telemetry packages"
  for p in $OOS_TEL; do
    if ! pkg_present "$p"; then s=absent
    elif pkg_disabled "$p"; then s=disabled
    else s=ENABLED; fi
    printf '   %-9s %s\n' "$s" "$p"
  done
  echo
  echo "-- opt-in: GMS location reporting (feat_gmsloc=$feat_gmsloc)"
  for c in $GMS_LOC; do
    if ! comp_exists "$c"; then s=absent
    elif comp_disabled "$c"; then s=disabled
    else s=ENABLED; fi
    printf '   %-9s %s\n' "$s" "$c"
  done
  echo
  echo "-- opt-in: GMS sensor appops (feat_gmsact=$feat_gmsact)"
  for o in $GMS_ACT_OPS; do
    printf '   %s\n' "$(cmd appops get --uid "$GMS" "$o" 2>/dev/null | head -1)"
  done
  echo
  echo "-- revert list (what uninstall will undo)"
  if [ -s "$STATE" ]; then sed 's/^/   /' "$STATE"; else echo "   nothing"; fi
}
