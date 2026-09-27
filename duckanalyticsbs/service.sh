#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"

(
  i=0
  while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 200 ]; do
    sleep 3
    i=$((i + 1))
  done
  [ "$(getprop sys.boot_completed)" = "1" ] || { log "boot never completed; giving up"; exit 0; }

  sleep 20
  [ "$feat_hungtask" = "1" ] && sysctl_apply
  log "boot pass start"
  apply_all
  log "boot pass done: gms $(count_comp_applied "$GMS_TEL")/$(count_comp_present "$GMS_TEL") oos $(count_pkg_applied)/$(count_pkg_present)"

  if [ "$feat_peach" = "1" ] && is_peach; then
    if ! peach_on; then
      log "backing file absent or not carrying $KEY - regenerating from stock"
      peach_turn_on || log "regenerate FAILED - still inert"
    elif peach_on && ! peach_active; then
      log "redirect missing after mount pass - re-adding"
      peach_redirect_add
      peach_active && reload_wifi
    elif peach_on && peach_active && recent_flood; then
      log "driver read stock before the mount pass - cycling Wi-Fi"
      reload_wifi
    fi
  fi

  set_card live
) &
