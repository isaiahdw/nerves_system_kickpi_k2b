# Changelog

## v0.1.0

Initial release, supporting KickPi K2B board revision 2.2.

* Mainline Linux 6.18 with the K2B device tree (rev 2.2 fixups: Maxio
  PHY reset timing, DDR3L rail held at its training voltage)
* Maxio MAE0621A-Q2C gigabit PHY driver (crystal clock mode) and the
  dwmac-sun8i probe ordering it requires
* Mainline U-Boot v2026.01 with the rev 2.2 DDR3L-1333 DRAM
  configuration, TF-A BL31 (sun50i_h616), KASLR seeding from the SoC
  TRNG
* Standard Nerves A/B firmware layout on the SD card with extlinux
  fallback boot
