# OpenWrt for TP-Link EX520v

Fully open-source OpenWrt support for the TP-Link EX520v (Türk Telekom AX3000,
MT7981B + MT7976, 512 MiB SPI-NAND, 512 MiB RAM). Every image can be rebuilt
from this repository: upstream OpenWrt at a pinned commit, one device-support
patch, and pinned package feeds.

> **Status: experimental.** See "Tested" below for what has been verified on
> real hardware.

[Türkçe](#türkçe)

## Why

A port for this router already exists, but it ships as prebuilt images only:
no device tree, no patches, no build recipe. Its installer also formats the
stock firmware's backup slot and several TP-Link data partitions, so going
back to stock needs a serial console.

This repository differs in three ways:

- **Source only.** `patches/` holds the device support (device tree, image
  recipe, board scripts). `build.sh` and the CI workflow rebuild everything.
- **No UART needed.** Installation uses a root shell on the stock firmware
  and the bootloader's own A/B slot mechanism.
- **Reversible.** OpenWrt lives in the slot TP-Link calls `ubi0`. The stock
  firmware stays untouched in slot `ubi1`, together with all TP-Link
  partitions (calibration, config, backups).

## How the stock bootloader works

The stock boot chain is BL2 → first U-Boot → second U-Boot (`uboot` volume
of the selected slot) → kernel. The first U-Boot matches TP-Link's GPL
source (`board/mediatek/common/ubi_helper.c`, `CONFIG_TP_FIRST_UBOOT`):

- The U-Boot env variable `tp_boot_idx` selects the slot: `1` means MTD
  `ubi1`, anything else means MTD `ubi0`.
- The first U-Boot reads the `uboot`, `rootfs` and `kernel` volumes of that
  slot. If any of them is missing, empty, interrupted mid-update or
  unreadable, it switches to the other slot and saves `tp_boot_idx`.
- It does **not** fall back when a kernel starts and then hangs. There is no
  boot counter and no web recovery on this model.
- The second U-Boot runs `bootm` on the FIT image from the `kernel` volume.
  It accepts unsigned FIT images and allows up to 64 MiB of decompressed
  kernel (`CONFIG_SYS_BOOTM_LEN`).

TP-Link's own `/usr/bin/do_upgrade.sh` upgrades the inactive slot in exactly
this way: `ubiformat`, static `uboot`/`kernel`/`rootfs` volumes, then
`fw_setenv tp_boot_idx`. The installer here does the same.

## Safe installation

The install is split into steps, and each step leaves a way back.

1. **Backup** (`install/backup-stock.sh`, run on a PC). Reads every MTD
   partition over SSH. Keep this backup: `misc_ro` holds this unit's Wi-Fi
   calibration and MAC addresses.
2. **Trial boot from RAM** (`install/stock-install-trial.sh`, run on stock).
   Writes the initramfs image into slot `ubi0`, then sets `ex520v_trial=1`
   and clears `tp_boot_idx`. On its next boot, OpenWrt's first preinit step
   sets `tp_boot_idx=1` again (`files/lib/preinit/05_ex520v_trial`). A power
   cycle therefore always returns to stock until you confirm the install.
3. **Write to flash** (`install/openwrt-trial-to-flash.sh`, run on the trial
   OpenWrt). Writes the sysupgrade image into slot `ubi0` and checks that the
   new root filesystem mounts. The next boot is still a trial boot.
4. **Confirm** (`install/openwrt-confirm.sh`, run on OpenWrt booted from
   flash). Clears `ex520v_trial` and `tp_boot_idx`.

To return to stock at any time from OpenWrt:

```sh
fw_setenv ex520v_trial; fw_setenv tp_boot_idx 1; reboot
```

**Remaining risk:** if a kernel crashes before userspace starts, the router
keeps booting slot `ubi0`, and only a serial console (UART) can recover it.
The trial boot in step 2 exists to catch this with a RAM-only image before
anything is written for real. BL2, FIP and the bootloader env layout are
never modified, so the device can always be recovered over UART.

## Hardware notes

| | |
|---|---|
| SoC | MediaTek MT7981B, 2× Cortex-A53 |
| Flash | 512 MiB Micron SPI-NAND with NMBM (managed area: last 128 blocks) |
| Switch | MT7531 on GMAC0 (2500base-x). Ports: lan1 = 3, lan2 = 2, lan3 = 1 |
| WAN | GMAC1 with the internal GbE PHY |
| Wi-Fi calibration | `misc_ro` UBIFS, file `0x00440000` (first 4 KiB) |
| MAC base | `misc_ro` UBIFS, file `0x0038F1E0`. WAN +1, LAN +5, 2.4 GHz +6, 5 GHz +7, the same offsets stock uses |
| Not supported | FXS phone port (Si3218x SLIC) |

Türk Telekom fibre uses PPPoE on VLAN 35 (`eth1.35`).

## Building

```sh
./build.sh            # Debian/Ubuntu host with OpenWrt build dependencies
```

The images land in `openwrt/bin/targets/mediatek/filogic/`:

- `*-initramfs-kernel.bin`: the trial image
- `*-squashfs-sysupgrade.bin`: the flash image

## Tested

Verified on a live unit (2026-09-26):

- [x] Trial boot from RAM (initramfs)
- [x] Flash boot from `ubi0`, persistent `ubifs` overlay on `rootfs_data`
- [x] WAN: PPPoE over `eth1.35` (Türk Telekom fibre), public IP + DNS
- [x] Wi-Fi 2.4 GHz (ch1/HE20) and 5 GHz (ch36/HE80) up with factory calibration
- [x] Return to stock by power-cycle while `ex520v_trial=1`, and via `tp_boot_idx=1`
- [ ] LAN1-LAN3 throughput, LEDs, buttons, USB (not yet exercised)

---

## Türkçe

TP-Link EX520v (Türk Telekom AX3000) için tamamen açık kaynaklı OpenWrt
desteği. Tüm imajlar bu depodan yeniden derlenebilir: sabitlenmiş bir
upstream OpenWrt commit'i, tek bir cihaz desteği patch'i ve sabitlenmiş
paket feed'leri.

- **Kurulum için UART gerekmez.** Stok firmware'deki root erişimi ve
  bootloader'ın kendi A/B slot mekanizması kullanılır.
- **Geri alınabilir.** OpenWrt `ubi0` slotuna kurulur. Stok firmware `ubi1`
  slotunda, TP-Link'in tüm bölümleriyle birlikte (kalibrasyon, ayarlar,
  yedekler) dokunulmadan kalır.
- **Deneme açılışı.** OpenWrt her açılışta ilk iş olarak bir sonraki açılışı
  stok slota yönlendirir. Kurulumu onaylayana kadar routerı kapatıp açmak
  stok firmware'e döndürür.
- **Kalan risk:** Kernel, userspace'e geçmeden çökerse kurtarmak için UART
  gerekir. İlk deneme bu yüzden flash'a hiçbir şey kalıcı yazmadan, RAM'den
  açılan bir imajla yapılır.

Stoka dönmek için:

```sh
fw_setenv ex520v_trial; fw_setenv tp_boot_idx 1; reboot
```

Telefon (FXS) portu desteklenmez.

## License

The device support is GPL-2.0-or-later (device tree: GPL-2.0-or-later OR
MIT), like upstream OpenWrt. The install scripts are GPL-2.0-or-later.
