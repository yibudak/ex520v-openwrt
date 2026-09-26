#!/bin/sh
# Builds OpenWrt for the TP-Link EX520v from pinned upstream sources plus the
# device support patch in patches/. Output: openwrt/bin/targets/mediatek/filogic/
#
# Usage: ./build.sh [jobs]

set -e

OPENWRT_URL=https://github.com/openwrt/openwrt.git
OPENWRT_COMMIT=44b73b738d18e424d86a34be3fb1d93cf3d718d6   # openwrt-25.12

TOP=$(cd "$(dirname "$0")" && pwd)
JOBS="${1:-$(nproc)}"

if [ ! -d "$TOP/openwrt/.git" ]; then
	git clone "$OPENWRT_URL" "$TOP/openwrt"
fi
cd "$TOP/openwrt"
git checkout -q "$OPENWRT_COMMIT"
git checkout -q -B ex520v
git -c user.name=build -c user.email=build@localhost am -q "$TOP"/patches/*.patch

cp "$TOP/config/feeds.conf" feeds.conf
./scripts/feeds update -a
./scripts/feeds install -a

cp "$TOP/config/ex520v.diffconfig" .config
make defconfig

rm -rf files
cp -R "$TOP/files" files

make -j"$JOBS" download
make -j"$JOBS" world
ls -l bin/targets/mediatek/filogic/
