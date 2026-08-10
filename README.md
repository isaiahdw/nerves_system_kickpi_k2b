# Nerves System: KickPi K2B

Nerves system for the [KickPi K2B](https://www.kickpi.com/product/k2b/)
**revision 2.2**, an Allwinner H618 single-board computer (quad
Cortex-A53, Mali-G31 MP2, 2 GB DDR3L, eMMC, gigabit Ethernet, Seekwave
WiFi 5/BT, USB-C power).

This system supports the rev 2.2 hardware:

| | rev 1.x | rev 2.2 (this system) |
| --- | --- | --- |
| DRAM | LPDDR4 | DDR3L-1333 (different U-Boot DRAM config) |
| Ethernet PHY | (v1 part) at MDIO 0 | Maxio MAE0621A-Q2C at MDIO 0 |
| WiFi/BT | AIC8800 module | Seekwave VS6621S (SDIO 1FFE:6621) |

A rev 1.x board will not boot this image (the SPL stops at DRAM init);
it needs the LPDDR4 U-Boot defconfig from the Armbian board support
instead.

| Feature | Status |
| --- | --- |
| CPU | 4x Cortex-A53, DVFS 480-1416 MHz (speed-bin OPPs) |
| SD card | mmcblk0 (the boot device) |
| eMMC | mmcblk2, HS200; the boot script follows the boot medium |
| Ethernet | `eth0`, gigabit — Maxio vendor PHY driver (linux/0002/0003) |
| WiFi | `wlan0` — Seekwave vendor driver (linux/0004) + firmware, autoloads |
| Bluetooth | skwbt module loads; stack bring-up not attempted yet |
| USB | 2x USB 2.0 host + header USB pair; USB-C peripheral (gadget) |
| HDMI | DE33 pipeline (linux/0101-0141): kernel console + `/dev/fb0`, KMS |
| GPU | Panfrost kernel driver; no Mesa userspace in the image |
| RTC | Battery-backed TCS8563 on i2c3, `rtc0` (SoC RTC is `rtc1`) |
| PWM | 6-channel controller; pwm1/pwm2 on header pins 10/8 |
| IR | Receiver on PH10, NEC decode |
| UART console | UART0, 115200 — GPIO header pins 15 (RX) / 17 (TX) / 19 (GND) |
| LED | Blue status LED (PI16), heartbeat trigger |
| Hardware RNG | Crypto-engine TRNG via BL31 SMCCC — `/dev/hwrng` and KASLR seed |

## Boot flow and disk layout

Boot ROM → `u-boot-sunxi-with-spl.bin` (SPL + TF-A BL31 + U-Boot) at the
fixed 8 KB offset on the SD card → Nerves U-Boot environment at 4 MB →
`Image.<slot>` + dtb from the FAT partition → squashfs rootfs.

MBR partitions (GPT would collide with the SPL at 8 KB): p1 FAT32 boot,
p2/p3 rootfs A/B (squashfs, 512 MB each), p4 application data (f2fs,
grows to fill the card).

A/B updates follow the standard Nerves model: `nerves_init` in the saved
environment picks the slot and reverts unvalidated firmware; if the
environment is missing or corrupt, U-Boot's compiled-in distro boot falls
back to `extlinux/extlinux.conf` on the FAT partition, which fwup points
at the new slot on each upgrade (see the recovery caveat below for the
automatic-revert case).

The H618 boot ROM tries the SD card before the eMMC, so an SD card built
from this system always boots regardless of eMMC contents. The boot
script selects kernel, dtb and root from the boot medium; full
eMMC-primary operation (environment writes, application data and the
extlinux fallback all still name the SD paths) is future work.

## Hardware entropy

BL31 (TF-A) implements the Arm SMCCC TRNG interface backed by the
H616/H618 crypto-engine TRNG (`tfa/patches/arm-trusted-firmware/0001`).
The normal world consumes it two ways:

- Linux exposes it as `/dev/hwrng` through the `arm_smccc_trng` driver.
- U-Boot binds it as a `DM_RNG` device and `booti` seeds the kernel's
  KASLR from it. This needs `CONFIG_ARM_SMCCC_FEATURES` and
  `CONFIG_RNG_SMCCC_TRNG` (`uboot/fragment.config`) plus `arm,psci-1.0`
  in the control device tree (`uboot/patches/0003`), which U-Boot's
  SMCCC feature discovery requires to bind the driver.

The in-kernel crypto-engine driver is disabled
(`# CONFIG_CRYPTO_DEV_SUN8I_CE is not set` in `linux/nerves.config`) so
BL31 owns the engine; if Linux also bound it the two would race the same
task-queue registers, clocks and reset. As the sole user, BL31 re-enables
the CE clocks on each request (nothing else holds them on) and, at boot,
advertises the TRNG only after a self-test passes — a dead engine then
binds no RNG device and the normal world skips seeding rather than
hanging.

This is a hardware entropy *source*, not a secure or attested one: the CE
registers and BL31's descriptor/output buffers are reachable from the
non-secure world, so a hardware RNG for KASLR and `/dev/hwrng` is what it
provides, not a secure-world trust boundary.

## Board support provenance

The board is not upstream. The support is assembled from:

* `uboot/patches/0001` — mainline U-Boot v2026.01 plus
  `kickpi_k2b_defconfig`. The DRAM block is the rev 2.2 DDR3L-1333
  configuration from the vendor SDK (via the Armbian forum);
  `DRAM_CLK=648`, `AXP_DCDC3_VOLT=1360` (DDR3L rail, matched by the
  kernel DTS so the voltage never moves after training).
* `uboot/patches/010/011/012` — the rest of Armbian's K2B set: GPU
  power poke (panfrost needs it), THS SRAMC clear (kernel thermal
  needs it), DRAM-detect settle delay.
* `linux/0001` — the kernel device tree, reduced to nodes that exist in
  mainline 6.18, with rev 2.2 fixups (PHY reset settle, DRAM rail).
* `linux/0002` — Maxio MAE0621A PHY driver (immortalwrt's 6.18 port of
  the vendor driver), in **crystal clock mode** — without the crystal
  mode register write the PHY's ADC never calibrates and autoneg never
  completes. `CONFIG_MAXIO_PHY=y`.
* `linux/0003` — dwmac-sun8i: the probe-time MAC reset cannot succeed
  before the PHY driver has started the RGMII RX clock; warn instead of
  failing (the DMA reset at first open repeats it).

TF-A is `lts-v2.12.9` with `PLAT=sun50i_h616`.

## WiFi

The rev 2.2 module is a Seekwave VS6621S. `linux/0004` carries the
vendor driver tree (from pyavitz's debian-image-builder, with kernel
6.18 compat and modalias fixes); `package/seekwave-firmware` installs
the `SWT6621S_*` blobs, with the shared-antenna NV data at the
canonical name the driver requests. The stack autoloads through
hotplug: `skw_sdio_lite` from the SDIO id, then `swt6621s_wifi`
(creates `wlan0`) and `skwbt` from the platform devices it registers.
Configure with `vintage_net_wifi` as usual.

## Recovery caveat

The extlinux fallback is best-effort after an automatic revert: the
revert switches the Nerves environment but does not rewrite
`extlinux/extlinux.conf`, so until the next successful upgrade the
fallback file may still point at the rejected slot. It only matters if
the environment is also lost — a double failure.

## Release artifacts

No prebuilt system artifacts are published: the Seekwave WiFi firmware
has no documented redistribution grant, and a built artifact contains
those blobs. Build from source instead — the blobs are fetched at
build time with pinned hashes and never enter this repository.

## Building

```sh
git clone https://github.com/isaiahdw/nerves_system_kickpi_k2b.git
cd nerves_system_kickpi_k2b
mix deps.get
mix compile
```

Or use it as the target system of a Nerves project:

```elixir
{:nerves_system_kickpi_k2b, path: "../nerves_system_kickpi_k2b", runtime: false, targets: :kickpi_k2b}
```

Write firmware to an SD card with `fwup` / `mix burn` as usual; update a
running board over SSH with `mix upload`.

## Flashing the eMMC over USB (FEL)

The H618 boot ROM's FEL mode loads U-Boot into RAM over the USB-C OTG
port; U-Boot then exposes the eMMC to the host as a USB disk for `fwup`.
No SD card or bootable media is needed.

### Host setup (macOS)

`sunxi-fel` has no Homebrew formula; build it from source:

```sh
brew install libusb pkg-config
git clone https://github.com/linux-sunxi/sunxi-tools.git
cd sunxi-tools && make tools
```

### Procedure

1. Disconnect the serial adapter from the board. Stray current from an
   attached adapter back-powers the SoC and blocks FEL entry (and can
   corrupt the USB transfers).
2. Hold the recovery button (PC2, next to the GPIO header), plug the
   USB-C port into the host, then release the button. Verify:

   ```sh
   sunxi-fel ver   # AWUSBFEX soc=00001823(H616) ...
   ```

3. Load U-Boot into RAM:

   ```sh
   sunxi-fel uboot u-boot-sunxi-with-spl.bin
   ```

   The image is in the built system artifact under `images/`. U-Boot
   detects the FEL boot (`fel_booted=1`) and starts USB mass storage
   automatically — within a few seconds the eMMC enumerates on the host
   as an external disk. macOS asks for permission to access it; click
   Allow.

4. Write the firmware (check the disk number with `diskutil list
   external physical` first):

   ```sh
   diskutil unmountDisk force /dev/diskN
   fwup -a -t complete -d /dev/rdiskN -i my_app.fw
   ```

5. Unplug USB-C and power the board normally. The boot ROM boots the
   eMMC whenever no bootable SD card is present. The application
   partition is sized at first boot to fill the eMMC.

If a transfer times out or `sunxi-fel ver` stops answering, the FEL
state is wedged: power-cycle the board (with the serial adapter
disconnected) and re-enter FEL.

## Serial console

UART0 at 115200 8N1 on the 20-pin GPIO header: pin 15 = board RX,
pin 17 = board TX, pin 19 = GND (the three odd pins at the "20" end).

## Recovery

* Corrupt env: U-Boot distro boot falls back to the extlinux config on
  the FAT partition.
* Bad SD image: the H618 boot ROM's FEL USB recovery mode is reachable
  over the USB-C OTG port with no bootable media present (`sunxi-fel`
  from sunxi-tools).
