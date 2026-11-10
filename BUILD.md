# Derleme

## İmajın bileşenleri

| Bileşen | Dosya |
|---|---|
| OpenWrt 25.12 (sabit commit) | `build.sh` içinde `OPENWRT_COMMIT` |
| Paket feed'leri (sabit commit'ler) | `config/feeds.conf` |
| Cihaz desteği | `patches/0001-mediatek-filogic-add-TP-Link-EX520v-support.patch` |
| Derleme ayarları | `config/ex520v.diffconfig` |
| İlk açılış ayarları ve deneme modu | `files/` |

Depoda hazır binary yoktur. Wi-Fi firmware'i gibi binary parçalar, resmi
OpenWrt imajlarının da kullandığı OpenWrt paketlerinden gelir.

## GitHub Actions

`.github/workflows/build.yml`, GitHub'ın `ubuntu-24.04` runner'ında
`./build.sh` çalıştırır. İmajlara SHA-256 özetlerini ve bir attestation ekler,
ardından hepsini workflow artifact'ı olarak yükler.

Workflow `main` dalına yapılan her push'ta, pull request'lerde ve Actions
sekmesinden elle başlatıldığında çalışır. `v` ile başlayan bir etiket
push'landığında imajlar Releases sayfasına da eklenir.

Kendi hesabınızda derlemek için depoyu fork'layın. Fork'un Actions sekmesinde
**build** workflow'unu seçip **Run workflow** düğmesine tıklayın.

## İmajın doğrulanması

İmajın bu deponun workflow'u tarafından derlendiğini doğrulayın
([GitHub CLI](https://cli.github.com/) gerekir):

```sh
gh attestation verify openwrt-*-tplink_ex520v-squashfs-sysupgrade.bin \
  -R yibudak/ex520v-openwrt
```

Dosyanın indirme sırasında bozulmadığını doğrulayın:

```sh
sha256sum -c --ignore-missing SHA256SUMS.ex520v    # macOS: shasum -a 256 -c
```

## Yerel derleme

Gereksinimler:

- x86_64 Linux. CI, Ubuntu 24.04 kullanır. macOS'ta OrbStack, Windows'ta WSL2
  gibi bir Linux ortamı kurun.
- 25 GB boş disk alanı ve internet bağlantısı.
- Normal bir kullanıcı hesabı. Derlemeyi `root` olarak çalıştırmayın.

Bağımlılıkları kurun (CI'daki listenin aynısı):

```sh
sudo apt-get update
sudo apt-get install -y build-essential clang flex bison g++ gawk \
  gcc-multilib g++-multilib gettext git libncurses-dev libssl-dev \
  python3-setuptools python3-dev python3-pyelftools rsync swig unzip \
  zlib1g-dev file wget zstd
```

Derleyin:

```sh
git clone https://github.com/yibudak/ex520v-openwrt.git
cd ex520v-openwrt
./build.sh        # paralel iş sayısı için: ./build.sh 4
```

`build.sh` şu adımları uygular:

1. OpenWrt'yi `openwrt/` klasörüne klonlar ve sabit commit'e geçer.
2. `patches/` altındaki patch'i uygular.
3. Paket feed'lerini indirir ve kurar.
4. `config/ex520v.diffconfig`'ten `.config` üretir.
5. `files/` klasörünü imaja ekler.
6. Kaynakları indirir ve derler.

İlk derleme, toolchain'i de derlediği için uzun sürer. Sonraki derlemeler
hazır parçaları yeniden kullanır. Sıfırdan derlemek için
`rm -rf openwrt && ./build.sh` komutunu çalıştırın.

İmajlar `openwrt/bin/targets/mediatek/filogic/` klasöründe oluşur:

| Dosya | İşlevi |
|---|---|
| `*-tplink_ex520v-initramfs-kernel.bin` | Deneme imajı, RAM'den açılır |
| `*-tplink_ex520v-squashfs-sysupgrade.bin` | Flash imajı |
| `sha256sums` | Klasördeki dosyaların SHA-256 özetleri |

## Yerel derlemenin CI ile karşılaştırılması

OpenWrt, aynı kaynaktan aynı imajı üretmeyi hedefler. Dosya tarihlerini commit
tarihinden alır. `config/ex520v.diffconfig` de kernel'e yazılan kullanıcı ve
makine adını sabitler. Kendi imajınızın özetini alın:

```sh
sha256sum openwrt/bin/targets/mediatek/filogic/*tplink_ex520v*
```

Sonucu release'teki `SHA256SUMS.ex520v` ile karşılaştırın. Özetler farklı
çıkarsa iki imajın farkını [diffoscope](https://diffoscope.org/) ile
inceleyebilirsiniz.

## Değişiklik yapmak

- Paket eklemek için `config/ex520v.diffconfig` dosyasına
  `CONFIG_PACKAGE_<paket>=y` satırını ekleyin.
- İlk açılış ayarlarını değiştirmek için `files/etc/uci-defaults/` altındaki
  betikleri düzenleyin. `files/` altındaki her dosya imaja girer. Kendi Wi-Fi
  parolanızı ya da PPPoE bilginizi buraya koymayın.
- OpenWrt'yi güncellemek için `build.sh` içindeki `OPENWRT_COMMIT` değerini ve
  `config/feeds.conf` içindeki commit'leri aynı kararlı dalın yeni
  commit'leriyle değiştirin. Patch uygulanmazsa yeni tabana göre düzenleyin.
