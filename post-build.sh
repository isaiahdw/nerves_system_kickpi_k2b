#!/bin/sh

set -e

# Create the fwup ops script for on-device firmware operations (revert,
# validate, factory-reset, status)
# revert.fw is a symlink alias to ops.fw, retained for Nerves tooling that
# expects that filename.
mkdir -p $TARGET_DIR/usr/share/fwup
$HOST_DIR/usr/bin/fwup -c -f $NERVES_DEFCONFIG_DIR/fwup-ops.conf -o $TARGET_DIR/usr/share/fwup/ops.fw
ln -sf ops.fw $TARGET_DIR/usr/share/fwup/revert.fw

# Copy the fwup includes to the images dir
cp -rf $NERVES_DEFCONFIG_DIR/fwup_include $BINARIES_DIR
