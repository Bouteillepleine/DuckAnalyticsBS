#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"

case "$1" in
  status)
    status_json
    ;;
  report)
    report
    ;;
  measure)
    measure
    ;;
  apply)
    apply_all
    [ "$feat_peach" = "1" ] && is_peach && ! peach_active && peach_turn_on
    set_card live
    log "manual apply"
    ;;
  revert)
    revert_all
    set_card live
    log "manual revert"
    ;;
  on)
    feat_on "$2" || exit 1
    set_card live
    log "enabled $2"
    ;;
  off)
    feat_off "$2" || exit 1
    set_card live
    log "disabled $2"
    ;;
  log)
    tail -60 "$LOG" 2>/dev/null || echo "no log yet"
    ;;
  refresh)
    cache_drop
    build_cache && echo "component cache rebuilt: $(wc -l < "$CACHE") entries" || echo "rebuild failed"
    ;;
  *)
    echo "usage: ctl.sh {status|report|measure|apply|revert|log|refresh}"
    echo "       ctl.sh {on|off} {peach|gmstel|oostel|gmsloc|gmsact|wifiscan|hungtask|all}"
    ;;
esac
