#!/bin/sh
# Runs ON OpenWrt booted from flash (slot "ubi0") in trial mode. Makes the
# install permanent: slot ubi0 boots by default and the stock fallback is
# no longer re-armed on every boot. Stock stays in slot ubi1; to go back:
#   fw_setenv ex520v_trial; fw_setenv tp_boot_idx 1; reboot

set -e

. /lib/functions.sh

log() { echo "[ex520v] $*"; }
die() { log "ERROR: $*"; exit 1; }

[ "$(board_name)" = "tplink,ex520v" ] || die "not a TP-Link EX520v"
[ "$(awk '$2 == "/rom" { print $3; exit }' /proc/mounts)" = "squashfs" ] ||
	die "not running from flash"
grep -q '^/dev/ubiblock0_' /proc/mounts || die "root is not on slot ubi0"
[ "$(awk '$2 == "/overlay" { print $3; exit }' /proc/mounts)" = "ubifs" ] ||
	die "overlay is not on rootfs_data"

fw_setenv tp_boot_idx
fw_setenv ex520v_trial
fw_printenv -n tp_boot_idx >/dev/null 2>&1 && die "tp_boot_idx still set"
fw_printenv -n ex520v_trial >/dev/null 2>&1 && die "ex520v_trial still set"

log "DONE: OpenWrt is now the default; stock remains in slot ubi1"
