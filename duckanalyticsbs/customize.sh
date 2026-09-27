SKIPUNZIP=0

ui_print "- DuckAnalyticsBS"

SDK=$(getprop ro.build.version.sdk)
[ "${SDK:-0}" -lt 34 ] && ui_print "! SDK $SDK is below 34 - targets were verified on 36"

MODDIR=$MODPATH
. "$MODPATH/common.sh"

rm -f "/data/adb/$MODID.revert" "/data/adb/service.d/$MODID-revert.sh" 2>/dev/null

if [ -d "$LEGACY" ]; then
  ui_print "- superseding peach_roamstats_quiet"
  have_suite && "$NOMOUNT" vfs del "$VPATH" >/dev/null 2>&1
fi

if [ "$feat_peach" = "1" ] && is_peach; then
  if peach_generate; then
    ui_print "- peach_v2 INI patched from this device's own copy"
    peach_redirect_add >/dev/null 2>&1 && ui_print "- dmesg redirect live now, no gap until reboot"
  else
    ui_print "! could not patch peach_v2 INI now - will retry at boot"
    ui_print "  reason is in run.log"
  fi
else
  is_peach || ui_print "- no peach_v2 Wi-Fi here, dmesg feature is an inert no-op"
fi

if [ -d "$LEGACY" ]; then
  rm -f "$LEGACY/vendor/etc/wifi/peach_v2/WCNSS_qcom_cfg.ini" 2>/dev/null
  touch "$LEGACY/remove" 2>/dev/null
  ui_print "- peach_roamstats_quiet marked for removal"
fi

ui_print "- GMS and OxygenOS targets apply at boot, then verify"

set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in common.sh ctl.sh action.sh service.sh post-fs-data.sh uninstall.sh; do
  set_perm "$MODPATH/$f" 0 0 0755
done
