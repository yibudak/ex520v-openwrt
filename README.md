# TP-Link EX520v için OpenWrt

TP-Link EX520v (Türk Telekom AX3000, MT7981B + MT7976, 512 MiB SPI-NAND,
512 MiB RAM) için tamamen açık kaynaklı OpenWrt desteği. Tüm imajlar bu
depodan yeniden derlenebilir: sabitlenmiş bir upstream OpenWrt sürümü
(`openwrt-25.12`, kernel 6.12), tek
bir cihaz desteği patch'i ve sabitlenmiş paket feed'leri.

> **Durum: deneysel.** Gerçek donanımda neyin doğrulandığı aşağıdaki
> "Test edilenler" bölümünde.

## Varsayılan erişim

İlk açılışta Wi-Fi **otomatik açık** gelir; kablo gerekmez:

- SSID: **`OpenWrt-EX520v`** (2.4 GHz + 5 GHz)
- Wi-Fi parolası: **`openwrt-ex520v`** (WPA2)
- Yönetim: `http://192.168.1.1` (LuCI) — ilk açılışta root parolası boştur,
  hemen bir parola belirle.

> ⚠️ **Güvenlik:** Bu imajı kuran herkeste Wi-Fi SSID'i ve parolası **aynıdır**.
> İlk iş olarak LuCI → Network → Wireless'tan SSID ve parolayı, System →
> Administration'dan root parolasını değiştir. Değiştirene kadar Wi-Fi'ın
> herkese açık bir ortak parolası vardır.

Türk Telekom fiber için WAN, PPPoE + VLAN 35 (`eth1.35`) olarak önceden
ayarlıdır; yalnızca LuCI → Network → Interfaces → WAN'da kullanıcı adı ve
parolanı girmen yeterlidir.

## Neden

Bu router için zaten bir port var, ama yalnızca hazır imaj olarak dağıtılıyor:
device tree, patch ya da derleme tarifi yok. Kurulum aracı ayrıca stok
firmware'in yedek slotunu ve birkaç TP-Link veri bölümünü formatlıyor. Bu
yüzden stoka dönmek için seri konsol gerekiyor.

Bu depo üç noktada farklı:

- **Yalnızca kaynak.** `patches/` cihaz desteğini (device tree, imaj tarifi,
  board betikleri) içerir. `build.sh` ve CI workflow'u her şeyi yeniden
  derler.
- **UART gerekmez.** Kurulum, stok firmware'deki root shell'i ve
  bootloader'ın kendi A/B slot mekanizmasını kullanır.
- **Geri alınabilir.** OpenWrt, TP-Link'in `ubi0` dediği slota kurulur. Stok
  firmware tüm TP-Link bölümleriyle (kalibrasyon, ayarlar, yedekler) birlikte
  `ubi1` slotunda dokunulmadan kalır.

## Stok bootloader nasıl çalışır

Stok açılış zinciri şöyledir: BL2 → birinci U-Boot → ikinci U-Boot (seçili
slotun `uboot` volume'u) → kernel. Birinci U-Boot, TP-Link'in GPL kaynağıyla
(`board/mediatek/common/ubi_helper.c`, `CONFIG_TP_FIRST_UBOOT`) örtüşür:

- U-Boot env değişkeni `tp_boot_idx` slotu seçer: `1` MTD `ubi1` demektir,
  başka her değer MTD `ubi0` demektir.
- Birinci U-Boot o slotun `uboot`, `rootfs` ve `kernel` volume'larını okur.
  Bunlardan biri yoksa, boşsa, güncelleme yarıda kalmışsa ya da
  okunamıyorsa diğer slota geçer ve `tp_boot_idx`'i kaydeder.
- Kernel açılıp sonra takılırsa diğer slota **dönmez**. Bu modelde açılış
  sayacı ve web kurtarma yoktur.
- İkinci U-Boot, `kernel` volume'undaki FIT imajını `bootm` ile başlatır.
  İmzasız FIT imajlarını kabul eder ve 64 MiB'a kadar açılmış kernel'e izin
  verir (`CONFIG_SYS_BOOTM_LEN`).

TP-Link'in kendi `/usr/bin/do_upgrade.sh` betiği pasif slotu tam olarak bu
şekilde günceller: `ubiformat`, statik `uboot`/`kernel`/`rootfs` volume'ları,
ardından `fw_setenv tp_boot_idx`. Buradaki kurulum betiği de aynısını yapar.

## Güvenli kurulum

Kurulum adımlara bölünmüştür ve her adım bir geri dönüş yolu bırakır.

1. **Yedek** (`install/backup-stock.sh`, bilgisayarda çalışır). Tüm MTD
   bölümlerini SSH üzerinden okur. Bu yedeği sakla: `misc_ro`, bu cihaza
   özel Wi-Fi kalibrasyonunu ve MAC adreslerini tutar.
2. **RAM'den deneme açılışı** (`install/stock-install-trial.sh`, stokta
   çalışır). Initramfs imajını `ubi0` slotuna yazar, ardından
   `ex520v_trial=1` ayarlar ve `tp_boot_idx`'i temizler. Sonraki açılışta
   OpenWrt'nin ilk preinit adımı `tp_boot_idx=1`'i yeniden ayarlar
   (`files/lib/preinit/05_ex520v_trial`). Bu sayede kurulumu onaylayana kadar
   routerı kapatıp açmak her zaman stoka döndürür.
3. **Flash'a yazma** (`install/openwrt-trial-to-flash.sh`, deneme
   OpenWrt'sinde çalışır). Sysupgrade imajını `ubi0` slotuna yazar ve yeni
   kök dosya sisteminin bağlanabildiğini kontrol eder. Sonraki açılış hâlâ
   bir deneme açılışıdır.
4. **Onay** (`install/openwrt-confirm.sh`, flash'tan açılmış OpenWrt'de
   çalışır). `ex520v_trial` ve `tp_boot_idx`'i temizler.

OpenWrt'den istediğin an stoka dönmek için:

```sh
fw_setenv ex520v_trial; fw_setenv tp_boot_idx 1; reboot
```

**Kalan risk:** Kernel, userspace başlamadan çökerse router `ubi0` slotundan
açılmaya devam eder ve yalnızca seri konsol (UART) ile kurtarılabilir. 2.
adımdaki deneme açılışı, flash'a kalıcı bir şey yazılmadan önce bu durumu
yalnızca RAM'de çalışan bir imajla yakalamak için vardır. BL2, FIP ve
bootloader env düzeni hiç değiştirilmez, bu yüzden cihaz her zaman UART ile
kurtarılabilir.

## Donanım notları

| | |
|---|---|
| SoC | MediaTek MT7981B, 2× Cortex-A53 |
| Flash | 512 MiB Micron SPI-NAND, NMBM ile (yönetilen alan: son 128 blok) |
| Switch | GMAC0'da MT7531 (2500base-x). Portlar: lan1 = 3, lan2 = 2, lan3 = 1 |
| WAN | Dahili GbE PHY ile GMAC1 |
| Wi-Fi kalibrasyonu | `misc_ro` UBIFS, `0x00440000` dosyası (ilk 4 KiB) |
| MAC tabanı | `misc_ro` UBIFS, `0x0038F1E0` dosyası. WAN +1, LAN +5, 2.4 GHz +6, 5 GHz +7; stokla aynı offset'ler |
| Desteklenmeyen | FXS telefon portu (Si3218x SLIC) |

Türk Telekom fiber, VLAN 35 üzerinden PPPoE kullanır (`eth1.35`).

## Derleme

```sh
./build.sh            # OpenWrt derleme bağımlılıkları kurulu Debian/Ubuntu
```

İmajlar `openwrt/bin/targets/mediatek/filogic/` altına düşer:

- `*-initramfs-kernel.bin`: deneme imajı
- `*-squashfs-sysupgrade.bin`: flash imajı

## Güven ve doğrulama

Amaç, "benim derlediğim binary'e güven" değil; **binary'e hiç güvenmek
zorunda kalmaman.**

- **Kaynak açık ve küçük.** Cihaza özel her şey `patches/` (device tree +
  board betikleri, ~360 satır) ve `files/` içinde; dakikalar içinde okunur.
  Geri kalanı olduğu gibi upstream OpenWrt.
- **Girdiler sabitli.** `build.sh` upstream OpenWrt commit'ini, `config/feeds.conf`
  ise paket feed commit'lerini sabitler. "Şu anki her neyse" değil, tam belirli
  kaynak derlenir.
- **Kendin derle.** `./build.sh` ile aynı imajı sen üretirsin. Kimseye
  bağımlı değilsin.
- **Yeniden üretilebilir.** Kernel derleyici kimliği (`BUILD_USER/DOMAIN`)
  sabitlendiği için aynı kaynaktan çıkan imaj derleyene göre değişmez;
  yerelde derleyip release'in sha256'sıyla karşılaştırabilirsin.
- **CI açıkta derler.** GitHub Actions imajı bu repodan üretir, build log'u
  herkese açıktır ve release dosyalarına **build provenance attestation**
  eklenir: `gh attestation verify <dosya> -R <owner>/<repo>` ile dosyanın bu
  workflow tarafından bu kaynaktan üretildiği kriptografik doğrulanır.
- **Nihai hedef upstream.** Cihaz desteği OpenWrt'ye merge edilirse, resmi
  OpenWrt imajı (OpenWrt'nin kendi altyapısı derler) yeterli olur; bu repoya
  gerek kalmaz.

## Test edilenler

Çalışan bir cihazda doğrulandı (2026-09-26):

- [x] RAM'den deneme açılışı (initramfs)
- [x] `ubi0`'dan flash açılışı, `rootfs_data` üzerinde kalıcı `ubifs` overlay
- [x] WAN: `eth1.35` üzerinden PPPoE (Türk Telekom fiber), public IP + DNS
- [x] Fabrika kalibrasyonuyla Wi-Fi 2.4 GHz (ch1/HE20) ve 5 GHz (ch36/HE80)
- [x] `ex520v_trial=1` iken kapatıp açarak ve `tp_boot_idx=1` ile stoka dönüş
- [ ] LAN1-LAN3 hızı, LED'ler, butonlar, USB (henüz denenmedi)

## Lisans

Cihaz desteği, upstream OpenWrt gibi GPL-2.0-or-later lisanslıdır (device
tree: GPL-2.0-or-later OR MIT). Kurulum betikleri GPL-2.0-or-later
lisanslıdır.
