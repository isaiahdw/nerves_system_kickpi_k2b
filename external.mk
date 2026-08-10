# Include system-specific packages
include $(sort $(wildcard $(NERVES_DEFCONFIG_DIR)/package/*/*.mk))

# Buildroot sets a package's source up once, when it first extracts it, and
# keeps nothing that would notice the inputs to that step changing afterwards.
# It rebuilds from the tree it already has and reports success, so an edited
# patch or an edited local source file just quietly is not in the image.
#
# Hash those inputs and keep the hash inside the extracted tree. When it no
# longer matches, the tree is stale: delete it and the next step extracts and
# patches a fresh one.
#
# The checks run only for a goal that builds, and only once. Deleting a build
# directory is not a thing to do while merely reading a makefile for
# `make source`, `make legal-info` or a variable query, and a recursive make
# reparsing this must not delete a tree the outer one is using.
#
# The marker is exported, so a nested make sees it already set and skips.
# MAKELEVEL cannot be used for this: buildroot is not invoked at the top level
# here, so requiring level 0 disables the check altogether.
#
# := on the check and = order matter: the value is captured before the marker
# is set, or this make would skip itself.
#
# An empty MAKECMDGOALS is the default goal, which builds - and plain `make` in
# the build directory is what buildroot itself tells you to run, so it has to be
# covered. -n and -q ask what would happen rather than doing it, and must not
# delete anything.
#
# A dry run appears in MAKEFLAGS two different ways, and both have to be read.
# GNU make packs short flags into the first word with no leading dash, so -n
# among others shows up as a letter in something like "rRn". But it can also
# arrive as a separate word: `make -n --no-print-directory` yields
# " --no-print-directory -n", where the first word is the long option and the
# -n is at the end. Searching only the first word misses that, and searching it
# without excluding long options matches the "n" in --no-print-directory and
# disables the check on every real build. Both mistakes have been made here.
#
# So: letters from the first word only when it is not a long option, plus the
# exact spellings anywhere in the list.
NERVES_BUILD_GOALS = all world
NERVES_DRY_RUN_WORDS = -n -q --dry-run --just-print --recon --question
NERVES_SHORT_FLAGS = $(filter-out -%,$(firstword $(MAKEFLAGS)))
NERVES_DRY_RUN = $(strip \
	$(foreach f,n q,$(findstring $(f),$(NERVES_SHORT_FLAGS))) \
	$(filter $(NERVES_DRY_RUN_WORDS),$(MAKEFLAGS)))
NERVES_WANTS_BUILD = \
	$(if $(MAKECMDGOALS),$(filter $(NERVES_BUILD_GOALS),$(MAKECMDGOALS)),default)
NERVES_STALE_CHECK := \
	$(if $(NERVES_STALE_CHECKED),,$(if $(NERVES_DRY_RUN),,$(NERVES_WANTS_BUILD)))
export NERVES_STALE_CHECKED := 1

# $(1) build directory, $(2) stamp file, $(3) hash the stamp must hold.
define nerves-discard-if-stale
$(if $(NERVES_STALE_CHECK),$(shell \
	if [ -d "$(1)" ] && [ "$$(cat $(2) 2>/dev/null)" != "$(3)" ]; then \
		rm -rf "$(1)"; \
	fi))
endef

# /dev/null keeps cat off stdin when a set is empty.
nerves-hash = $(shell cat /dev/null $(1) | sha256sum | cut -d' ' -f1)

# The kernel: linux/*.patch, applied at extract, and the config
# fragment, folded in at configure.
NERVES_LINUX_PATCH_HASH = \
	$(call nerves-hash,$(sort $(wildcard $(NERVES_DEFCONFIG_DIR)/linux/*.patch)) \
		$(NERVES_DEFCONFIG_DIR)/linux/nerves.config)
NERVES_LINUX_PATCH_STAMP = $(LINUX_DIR)/.nerves-linux-patch-hash

# The env image: mkenvimage runs once at host-uboot-tools install, so
# an edited uboot.env otherwise never reaches uboot-env.bin.
NERVES_UBOOT_ENV_HASH = \
	$(call nerves-hash,$(NERVES_DEFCONFIG_DIR)/uboot/uboot.env)
NERVES_UBOOT_ENV_STAMP = $(HOST_UBOOT_TOOLS_DIR)/.nerves-env-hash

# TF-A patches, applied at extract via BR2_GLOBAL_PATCH_DIR. Both the
# U-Boot input hash (the U-Boot build bundles BL31) and the TF-A input
# hash below invalidate on these, so name the set once.
NERVES_TFA_PATCHES = \
	$(sort $(wildcard $(NERVES_DEFCONFIG_DIR)/tfa/patches/arm-trusted-firmware/*.patch))

# U-Boot: uboot/patches/*.patch, applied at extract, and the config
# fragment, merged at configure. The U-Boot build bundles BL31 into
# u-boot-sunxi-with-spl.bin (the SPL FIT), so the TF-A patches are inputs
# too — without them a TF-A-only change rebuilds bl31.bin but U-Boot
# keeps the old copy embedded in the combined image.
NERVES_UBOOT_INPUT_HASH = \
	$(call nerves-hash,$(sort $(wildcard $(NERVES_DEFCONFIG_DIR)/uboot/patches/*.patch)) \
		$(NERVES_TFA_PATCHES) \
		$(NERVES_DEFCONFIG_DIR)/uboot/fragment.config)
NERVES_UBOOT_STAMP = $(UBOOT_DIR)/.nerves-uboot-input-hash

# The WiFi/BT firmware: the files are downloads, but which files and
# where they are installed is decided by the package makefile here.
NERVES_SEEKWAVE_FW_HASH = \
	$(call nerves-hash,$(sort $(wildcard $(NERVES_DEFCONFIG_DIR)/package/seekwave-firmware/*)))
NERVES_SEEKWAVE_FW_DIR = $(BUILD_DIR)/seekwave-firmware-$(SEEKWAVE_FIRMWARE_VERSION)
NERVES_SEEKWAVE_FW_STAMP = $(NERVES_SEEKWAVE_FW_DIR)/.nerves-pkg-hash

# TF-A tree staleness. The CE TRNG driver is a new source file, so an
# edited patch that never re-extracts would silently ship stale BL31.
NERVES_TFA_PATCH_HASH = $(call nerves-hash,$(NERVES_TFA_PATCHES))
NERVES_TFA_PATCH_STAMP = $(ARM_TRUSTED_FIRMWARE_DIR)/.nerves-tfa-patch-hash

NERVES_STALE_DISCARDED := \
	$(call nerves-discard-if-stale,$(LINUX_DIR),$(NERVES_LINUX_PATCH_STAMP),$(NERVES_LINUX_PATCH_HASH)) \
	$(call nerves-discard-if-stale,$(UBOOT_DIR),$(NERVES_UBOOT_STAMP),$(NERVES_UBOOT_INPUT_HASH)) \
	$(call nerves-discard-if-stale,$(HOST_UBOOT_TOOLS_DIR),$(NERVES_UBOOT_ENV_STAMP),$(NERVES_UBOOT_ENV_HASH)) \
	$(call nerves-discard-if-stale,$(ARM_TRUSTED_FIRMWARE_DIR),$(NERVES_TFA_PATCH_STAMP),$(NERVES_TFA_PATCH_HASH)) \
	$(call nerves-discard-if-stale,$(NERVES_SEEKWAVE_FW_DIR),$(NERVES_SEEKWAVE_FW_STAMP),$(NERVES_SEEKWAVE_FW_HASH))

define NERVES_LINUX_RECORD_PATCH_HASH
	echo $(NERVES_LINUX_PATCH_HASH) > $(NERVES_LINUX_PATCH_STAMP)
endef
LINUX_POST_PATCH_HOOKS += NERVES_LINUX_RECORD_PATCH_HASH

define NERVES_UBOOT_RECORD_INPUT_HASH
	echo $(NERVES_UBOOT_INPUT_HASH) > $(NERVES_UBOOT_STAMP)
endef
UBOOT_POST_PATCH_HOOKS += NERVES_UBOOT_RECORD_INPUT_HASH

define NERVES_UBOOT_ENV_RECORD_HASH
	echo $(NERVES_UBOOT_ENV_HASH) > $(NERVES_UBOOT_ENV_STAMP)
endef
HOST_UBOOT_TOOLS_POST_INSTALL_HOOKS += NERVES_UBOOT_ENV_RECORD_HASH

define NERVES_SEEKWAVE_FW_RECORD_HASH
	echo $(NERVES_SEEKWAVE_FW_HASH) > $(NERVES_SEEKWAVE_FW_STAMP)
endef
SEEKWAVE_FIRMWARE_POST_EXTRACT_HOOKS += NERVES_SEEKWAVE_FW_RECORD_HASH

define NERVES_TFA_RECORD_PATCH_HASH
	echo $(NERVES_TFA_PATCH_HASH) > $(NERVES_TFA_PATCH_STAMP)
endef
ARM_TRUSTED_FIRMWARE_POST_PATCH_HOOKS += NERVES_TFA_RECORD_PATCH_HASH
