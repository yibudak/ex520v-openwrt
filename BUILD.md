# Derleme

## İmaja neler giriyor

| Bileşen | Dosya |
|---|---|
| OpenWrt 25.12 (sabit commit) | `build.sh` içinde `OPENWRT_COMMIT` |
| Paket feed'leri (sabit commit'ler) | `config/feeds.conf` |
| Cihaz desteği | `patches/0001-mediatek-filogic-add-TP-Link-EX520v-support.patch` |
| Derleme ayarları | `config/ex520v.diffconfig` |
| İlk açılış ayarları ve deneme modu | `files/` |

Depoda hazır ikili dosya yok. Wi-Fi firmware'i gibi ikili parçalar, resmi
OpenWrt imajlarının da kullandığı OpenWrt paketlerinden gelir.

## GitHub Actions

`.github/workflows/build.yml`, GitHub'ın `ubuntu-24.04` runner'ında
`./build.sh` çalıştırır. İmajlara SHA-256 özetlerini ve bir attestation ekler,
sonra hepsini workflow artifact'ı olarak yükler.

Workflow `main`'e her push'ta, pull request'lerde ve Actions sekmesinden elle
başlatınca çalışır. `v` ile başlayan bir etiket push'larsan imajlar Releases
sayfasına da gider.

Kendi hesabında derlemek için depoyu fork'la. Fork'un Actions sekmesinde
**build** workflow'unu seç ve **Run workflow**'a bas.

## İmajı doğrulama

İmajı bu deponun workflow'unun derlediğini kontrol et
([GitHub CLI](https://cli.github.com/) gerekir):

```sh
gh attestation verify openwrt-*-tplink_ex520v-squashfs-sysupgrade.bin \
  -R yibudak/ex520v-openwrt
```

Dosyanın inerken bozulmadığını kontrol et:

```sh
sha256sum -c --ignore-missing SHA256SUMS.ex520v    # macOS: shasum -a 256 -c
```

## Kendin derle

Gerekenler:

- x86_64 Linux. CI, Ubuntu 24.04 kullanıyor. macOS'ta OrbStack, Windows'ta
  WSL2 gibi bir Linux ortamı kur.
- 25 GB boş disk ve internet bağlantısı.
- Normal bir kullanıcı hesabı. Derlemeyi `root` olarak çalıştırma.

Bağımlılıkları kur (CI'daki listenin aynısı):

```sh
sudo apt-get update
sudo apt-get install -y build-essential clang flex bison g++ gawk \
  gcc-multilib g++-multilib gettext git libncurses-dev libssl-dev \
  python3-setuptools python3-dev python3-pyelftools rsync swig unzip \
  zlib1g-dev file wget zstd
```

Derle:

```sh
git clone https://github.com/yibudak/ex520v-openwrt.git
cd ex520v-openwrt
./build.sh        # paralel iş sayısı için: ./build.sh 4
```

`build.sh` şunları yapar:

1. OpenWrt'yi `openwrt/` klasörüne klonlar ve sabit commit'e geçer.
2. `patches/` altındaki patch'i uygular.
3. Paket feed'lerini indirir ve kurar.
4. `config/ex520v.diffconfig`'ten `.config` üretir.
5. `files/` klasörünü imaja ekler.
6. Kaynakları indirir ve derler.

İlk derleme, toolchain'i de derlediği için uzun sürer. Sonraki derlemeler
hazır parçaları yeniden kullanır. Sıfırdan derlemek için
`rm -rf openwrt && ./build.sh` çalıştır.

İmajlar `openwrt/bin/targets/mediatek/filogic/` klasörüne düşer:

| Dosya | Ne işe yarar |
|---|---|
| `*-tplink_ex520v-initramfs-kernel.bin` | Deneme imajı, RAM'den açılır |
| `*-tplink_ex520v-squashfs-sysupgrade.bin` | Flash imajı |
| `sha256sums` | Klasördeki dosyaların SHA-256 özetleri |

## Kendi derlemeni CI ile karşılaştır

OpenWrt, aynı kaynaktan aynı imajı üretmeyi hedefler. Dosya tarihlerini commit
tarihinden alır. `config/ex520v.diffconfig` de kernel'e yazılan kullanıcı ve
makine adını sabitler. Kendi imajının özetini al:

```sh
sha256sum openwrt/bin/targets/mediatek/filogic/*tplink_ex520v*
```

Sonucu release'teki `SHA256SUMS.ex520v` ile karşılaştır. Özetler farklı
çıkarsa [diffoscope](https://diffoscope.org/) ile iki imajın farkını
görebilirsin.

## Değişiklik yapmak

- **Paket eklemek:** `config/ex520v.diffconfig`'e `CONFIG_PACKAGE_<paket>=y`
  satırını ekle.
- **İlk açılış ayarları:** `files/etc/uci-defaults/` altındaki betikleri
  düzenle. `files/` altındaki her dosya imaja girer. Kendi Wi-Fi parolanı ya da
  PPPoE bilgini buraya koyma.
- **OpenWrt'yi güncellemek:** `build.sh`'taki `OPENWRT_COMMIT`'i ve
  `config/feeds.conf`'taki commit'leri aynı kararlı dalın yeni commit'leriyle
  değiştir. Patch uygulanmazsa yeni tabana göre düzenle.
