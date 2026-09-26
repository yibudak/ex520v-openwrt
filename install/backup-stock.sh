#!/bin/sh
# Runs on the host. Reads every MTD partition of a stock EX520v over SSH
# (read-only) into <outdir>, plus the U-Boot env and live device tree.
#
# Usage: backup-stock.sh <outdir> [ssh target, default root@192.168.1.1]
# Set SSH to override the ssh command (e.g. SSH="sshpass -e ssh").

set -e

OUT="$1"
TARGET="${2:-root@192.168.1.1}"
SSH="${SSH:-ssh}"
[ -n "$OUT" ] || { echo "usage: $0 <outdir> [target]"; exit 1; }
mkdir -p "$OUT"

rsh() {
	# The stock firmware periodically rewrites /var/passwd; retry logins.
	for i in 1 2 3 4 5 6 7 8; do
		$SSH -o ConnectTimeout=8 -o LogLevel=ERROR "$TARGET" "$@" && return 0
		sleep 4
	done
	return 1
}

rsh 'cat /proc/mtd' > "$OUT/proc_mtd.txt"
rsh 'fw_printenv' > "$OUT/fw_printenv.txt"
rsh 'cat /sys/firmware/fdt' > "$OUT/stock.dtb"

grep '^mtd' "$OUT/proc_mtd.txt" | while IFS=': ' read -r dev size erase name; do
	name=$(echo "$name" | tr -d '"')
	case "$name" in spi0.0|whole) continue ;; esac
	echo "dumping $dev ($name)"
	rsh "cat /dev/$dev" < /dev/null > "$OUT/$dev-$name.bin"
	want=$((0x$size))
	got=$(wc -c < "$OUT/$dev-$name.bin" | tr -d ' ')
	[ "$got" = "$want" ] || { echo "short read on $dev: $got != $want"; exit 1; }
done

(cd "$OUT" && shasum -a 256 *.bin *.dtb > SHA256SUMS)
echo "backup complete: $OUT"
