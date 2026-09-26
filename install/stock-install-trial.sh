#!/bin/sh
# Runs ON the stock TP-Link EX520v firmware (root shell).
#
# Writes an OpenWrt image into the inactive stock slot (MTD "ubi0") exactly
# like TP-Link's own /usr/bin/do_upgrade.sh does (ubiformat, static volumes
# uboot/kernel/rootfs), then arms a trial boot:
#   ex520v_trial=1   OpenWrt re-points the bootloader at the stock slot
#                    (tp_boot_idx=1) as the first thing it does in preinit
#   tp_boot_idx      unset, so the next boot starts slot ubi0 (OpenWrt)
#
# The running stock slot (MTD "ubi1") is never touched. Nothing here reboots.
#
# Usage: stock-install-trial.sh <dir> [--check]
#   <dir> must contain kernel.bin, rootfs.bin and crc.txt
#   (crc.txt: "<ubicrc32> <size> <file>" per line, computed on the build
#   host; the stock busybox has no wc/stat/sha256sum)
#   --check only verifies the preconditions and files, and writes nothing

set -e

D="${1:-/tmp/ex520v}"
UBIDEV=20

log() { echo "[ex520v] $*"; }
die() { log "ERROR: $*"; exit 1; }

mtd_index() { grep "\"$1\"" /proc/mtd | cut -d: -f1 | sed 's/^mtd//'; }

# field <file> <n>: column n of the crc.txt line for file
field() { grep " $1\$" "$D/crc.txt" | cut -d' ' -f$2; }

expect_crc() {
	local file="$1" want got
	want=$(field "$file" 1)
	[ -n "$want" ] || die "no crc for $file"
	got=$(ubicrc32 "$D/$file")
	[ "$got" = "$want" ] || die "$file crc $got != $want"
	[ -n "$(field "$file" 2)" ] || die "no size for $file"
}

# --- preconditions -----------------------------------------------------------
[ "$(cat /proc/sys/kernel/hostname)" = "EX520v" ] ||
	die "this does not look like a TP-Link EX520v"
for p in boot u-boot-env misc_ro misc_rw ubi0 ubi1 bflag container; do
	[ -n "$(mtd_index $p)" ] || die "MTD $p missing, unexpected flash layout"
done
grep -q "ubi.mtd=ubi1" /proc/cmdline ||
	die "stock is not running from slot ubi1, refusing to touch ubi0"
[ "$(fw_printenv -n tp_boot_idx 2>/dev/null)" = "1" ] ||
	die "tp_boot_idx is not 1"

MTD=$(mtd_index ubi0)
[ -n "$MTD" ] || die "MTD ubi0 not found"
for n in /sys/class/ubi/ubi*/mtd_num; do
	[ -e "$n" ] || continue
	[ "$(cat "$n")" = "$MTD" ] && die "mtd$MTD is attached, refusing"
done

# The running slot is UBI device 0 (ubi.mtd=ubi1); reuse its second-stage
# bootloader, which is the one this unit is booting right now.
[ "$(cat /sys/class/ubi/ubi0/mtd_num)" = "$(mtd_index ubi1)" ] ||
	die "ubi0 is not the running slot"
[ "$(cat /sys/class/ubi/ubi0/ubi0_0/name)" = "uboot" ] ||
	die "running slot has no uboot volume at id 0"
cat /dev/ubi0_0 > "$D/uboot.bin"
[ "$(ubicrc32 "$D/uboot.bin")" = "$(ubicrc32 /dev/ubi0_0)" ] ||
	die "uboot copy mismatch"
grep -v " uboot.bin\$" "$D/crc.txt" > "$D/crc.tmp" || true
echo "$(ubicrc32 "$D/uboot.bin") $(cat /sys/class/ubi/ubi0/ubi0_0/data_bytes) uboot.bin" >> "$D/crc.tmp"
mv "$D/crc.tmp" "$D/crc.txt"

expect_crc uboot.bin
expect_crc kernel.bin
expect_crc rootfs.bin

if [ "$2" = "--check" ]; then
	log "CHECK OK: preconditions met, nothing written"
	exit 0
fi

# Same lock as TP-Link's do_upgrade.sh, so a TR-069 pushed upgrade cannot
# write the same slot concurrently.
LOCK=/var/tmp/firmware.lock
[ -e $LOCK ] && die "$LOCK exists, a stock upgrade may be running"
touch $LOCK
trap 'rm -f $LOCK' EXIT

# --- write slot ubi0 -----------------------------------------------------------
log "formatting mtd$MTD (slot ubi0)"
ubiformat "/dev/mtd$MTD" -y
ubiattach -m "$MTD" -d $UBIDEV
trap 'ubidetach -d $UBIDEV 2>/dev/null; rm -f $LOCK' EXIT

vol=0
for name in uboot kernel rootfs; do
	file="$D/$name.bin"
	size=$(field "$name.bin" 2)
	log "volume $vol $name ($size bytes)"
	ubimkvol /dev/ubi$UBIDEV -n $vol -N $name -t static -s "$size"
	ubiupdatevol /dev/ubi${UBIDEV}_$vol "$file"
	[ "$(ubicrc32 /dev/ubi${UBIDEV}_$vol)" = "$(ubicrc32 "$file")" ] ||
		die "read-back mismatch on $name"
	vol=$((vol + 1))
done

ubidetach -d $UBIDEV
trap 'rm -f $LOCK' EXIT

# --- arm the trial boot -------------------------------------------------------
# Order matters: if power fails in between, tp_boot_idx is still 1 (stock).
fw_setenv ex520v_trial 1
[ "$(fw_printenv -n ex520v_trial 2>/dev/null)" = "1" ] || die "could not set ex520v_trial"
fw_setenv tp_boot_idx
fw_printenv -n tp_boot_idx >/dev/null 2>&1 && die "tp_boot_idx still set"

log "DONE: slot ubi0 holds OpenWrt, next boot is a trial boot"
