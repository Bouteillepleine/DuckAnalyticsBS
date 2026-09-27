#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"

echo "Re-applying enabled features and verifying..."
echo
sh "$MODDIR/ctl.sh" apply >/dev/null 2>&1
report
echo
echo "Toggle features in the WebUI, or:"
echo "  sh $MODDIR/ctl.sh on gmsloc"
echo "  sh $MODDIR/ctl.sh off gmstel"
echo "  sh $MODDIR/ctl.sh revert"
