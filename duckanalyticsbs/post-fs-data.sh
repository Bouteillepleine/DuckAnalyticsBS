#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"

[ "$feat_hungtask" = "1" ] && sysctl_apply
set_card
