#!/bin/sh
# Runs ON OpenWrt while it is in trial mode: booted as initramfs from slot
# "ubi0" with the stock fallback armed (tp_boot_idx=1, ex520v_trial=1).
#
# Writes the sysupgrade image into slot ubi0 the way nand.sh lays it out
# (kernel, rootfs, rootfs_data; the stock "uboot" volume is kept), verifies
# the written volumes, and points the next boot at slot ubi0. The next boot
# is still a trial boot, so a power cycle after it returns to stock.
# Does not reboot.
#
# Usage: openwrt-trial-to-flash.sh <sysupgrade.bin>

set -e

. /lib/functions.sh

IMG="$1"
W=/tmp/ex520v-img
MNT=/tmp/ex520v-rootfs

log() { echo "[ex520v] $*"; }
die() { log "ERROR: $*"; exit 1; }

vol_id() {
	local v
	for v in /sys/class/ubi/ubi0/ubi0_*; do
		[ "$(cat "$v/name")" = "$1" ] && { echo "${v##*_}"; return 0; }
	done
	return 1
}

wait_node() {
	local i=0
	while [ ! -e "$1" ] && [ $i -lt 10 ]; do sleep 1; i=$((i + 1)); done
	[ -e "$1" ] || die "$1 did not appear"
}

write_vol() {
	local name="$1" file="$2" size id
	size=$(wc -c < "$file")
	ubimkvol /dev/ubi0 -N "$name" -s "$size" >/dev/null
	id=$(vol_id "$name") || die "volume $name not created"
	wait_node "/dev/ubi0_$id"
	ubiupdatevol "/dev/ubi0_$id" "$file"
	[ "$(head -c "$size" "/dev/ubi0_$id" | sha256sum | cut -d' ' -f1)" = \
	  "$(sha256sum < "$file" | cut -d' ' -f1)" ] || die "read-back mismatch on $name"
	log "wrote $name (volume $id, $size bytes)"
}

# --- preconditions -----------------------------------------------------------
[ -f "$IMG" ] || die "usage: $0 <sysupgrade.bin>"
[ "$(board_name)" = "tplink,ex520v" ] || die "not a TP-Link EX520v"
[ "$(cat /tmp/ex520v-trial 2>/dev/null)" = "armed" ] || die "trial fallback was not armed at boot"
[ "$(fw_printenv -n ex520v_trial 2>/dev/null)" = "1" ] || die "ex520v_trial is not set"
[ "$(fw_printenv -n tp_boot_idx 2>/dev/null)" = "1" ] || die "stock fallback (tp_boot_idx=1) is not armed"
[ "$(awk '$2 == "/" { print $3; exit }' /proc/mounts)" != "squashfs" ] ||
	die "not running from RAM (initramfs)"
grep -q '"ubi0"' /proc/mtd || die "MTD ubi0 missing"
[ "$(cat /sys/class/ubi/ubi0/mtd_num)" = "$(grep '"ubi0"' /proc/mtd | cut -d: -f1 | sed 's/^mtd//')" ] ||
	die "UBI device 0 is not slot ubi0"
vol_id uboot >/dev/null || die "slot ubi0 has no uboot volume"

sysupgrade -T "$IMG" || die "sysupgrade image check failed"

rm -rf "$W" && mkdir -p "$W"
tar -xf "$IMG" -C "$W"
K="$W/sysupgrade-tplink_ex520v/kernel"
R="$W/sysupgrade-tplink_ex520v/root"
[ -s "$K" ] && [ -s "$R" ] || die "kernel/root missing in image"

# --- write -------------------------------------------------------------------
for b in /dev/ubiblock0_*; do
	[ -e "$b" ] && ubiblock -r "/dev/ubi0_${b##*_}"
done
for name in kernel rootfs rootfs_data; do
	vol_id "$name" >/dev/null && ubirmvol /dev/ubi0 -N "$name"
done

write_vol kernel "$K"
write_vol rootfs "$R"
ubimkvol /dev/ubi0 -N rootfs_data -m >/dev/null
log "created rootfs_data (volume $(vol_id rootfs_data))"

# --- verify the new root filesystem mounts ------------------------------------
id=$(vol_id rootfs)
ubiblock -c "/dev/ubi0_$id"
wait_node "/dev/ubiblock0_$id"
mkdir -p "$MNT"
mount -t squashfs -o ro "/dev/ubiblock0_$id" "$MNT"
grep -q "^DISTRIB_TARGET='mediatek/filogic'" "$MNT/etc/openwrt_release" || die "unexpected rootfs content"
umount "$MNT"
ubiblock -r "/dev/ubi0_$id"

# --- boot slot ubi0 next, still as a trial ------------------------------------
fw_setenv tp_boot_idx
fw_printenv -n tp_boot_idx >/dev/null 2>&1 && die "tp_boot_idx still set"

log "DONE: reboot to start OpenWrt from flash (trial mode stays armed)"
