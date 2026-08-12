################################################################################
#
# seekwave-firmware
#
################################################################################

# SWT6621S WiFi/BT firmware. skw_boot.c requests the files by bare name
# ("SWT6621S_DRAM_SDIO.bin"), so they live directly in /lib/firmware.
SEEKWAVE_FIRMWARE_VERSION = 9376f3f259dc36fa7afab44798defa18eb2b6f94
SEEKWAVE_FIRMWARE_SITE = https://raw.githubusercontent.com/pyavitz/armbian-firmware/$(SEEKWAVE_FIRMWARE_VERSION)
SEEKWAVE_FIRMWARE_SOURCE = SWT6621S_DRAM_SDIO.bin
# The R000xx/R040xx entries are the vendor's regulatory/rate-table variants.
# Some are byte-identical in the upstream collection (R00001 == R04001, both
# .bin and .ini); each is still fetched under its requested name because
# skw_boot loads firmware by exact filename.
SEEKWAVE_FIRMWARE_EXTRA_DOWNLOADS = \
	SWT6621S_IRAM_SDIO.bin \
	SWT6621S_NV_SDIO.ini \
	SWT6621S_NV_SDIO_ALONE.bin \
	SWT6621S_NV_SDIO_SHARE.bin \
	SWT6621S_NV_for_test_alone.bin \
	SWT6621S_NV_for_test_share.bin \
	SWT6621S_SEEKWAVE_R00000.bin \
	SWT6621S_SEEKWAVE_R00000.ini \
	SWT6621S_SEEKWAVE_R00001.bin \
	SWT6621S_SEEKWAVE_R00001.ini \
	SWT6621S_SEEKWAVE_R04000.bin \
	SWT6621S_SEEKWAVE_R04000.ini \
	SWT6621S_SEEKWAVE_R04001.bin \
	SWT6621S_SEEKWAVE_R04001.ini \
	https://raw.githubusercontent.com/retro98boy/seekwave-swt6621s/b1b15016119cb21965fc64dd374e42f46f011bb4/drivers/swtbt4l/sv6160lite.nvbin
# Proprietary vendor blobs. No first-party redistribution grant could
# be verified (Seekwave publishes no firmware downloads or terms; the
# KickPi SDK states none), so these are fetched at build time rather
# than shipped in this repository, and are excluded from legal-info
# redistribution. A published system artifact would still contain
# them — resolve rights before publishing artifacts.
SEEKWAVE_FIRMWARE_LICENSE = PROPRIETARY (Seekwave)
SEEKWAVE_FIRMWARE_REDISTRIBUTE = NO

# The BT NV config comes from the pinned retro98boy/seekwave-swt6621s source
# above. The HCI driver requests sv6160lite.nvbin by name and fails BT init
# without it.
SEEKWAVE_FIRMWARE_ALL_FILES = \
	$(SEEKWAVE_FIRMWARE_SOURCE) $(notdir $(SEEKWAVE_FIRMWARE_EXTRA_DOWNLOADS))

define SEEKWAVE_FIRMWARE_EXTRACT_CMDS
	for f in $(SEEKWAVE_FIRMWARE_ALL_FILES); do \
		cp $(SEEKWAVE_FIRMWARE_DL_DIR)/$$f $(@D)/; \
	done
endef

# The driver requests SWT6621S_NV_SDIO.bin; the collection only ships
# the antenna-config variants. The K2B has a single shared WiFi/BT
# antenna, so the SHARE variant is the board's NV data.
define SEEKWAVE_FIRMWARE_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(TARGET_DIR)/lib/firmware
	for f in $(SEEKWAVE_FIRMWARE_ALL_FILES); do \
		$(INSTALL) -m 0644 $(@D)/$$f $(TARGET_DIR)/lib/firmware/; \
	done
	ln -sf SWT6621S_NV_SDIO_SHARE.bin \
		$(TARGET_DIR)/lib/firmware/SWT6621S_NV_SDIO.bin
endef

$(eval $(generic-package))

# No license text ships with the blobs (SEEKWAVE_FIRMWARE_LICENSE_FILES
# intentionally unset); provenance is the pinned collection above.
