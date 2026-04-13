#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Copyright (C) 2025 Vasiliy Kovalev <kovalev@altlinux.org>

set -eo pipefail
source "$(dirname "$0")/01-setup-env.sh"

help() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Clones, patches, configures, and builds the kernel (all by default)."
    echo ""
    echo "Commands:"
    echo "  clean    Clean the build directory."
    echo "  init     Re-initialize the kernel directory (re-clone and re-apply patches)."
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message."
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    help
    exit 0
fi

COMMAND=$1
PATCH_DIR="$CONTAINER_REPO_DIR/patches/kernel"

# Determine the configured kernel version from KERNEL_GIT_TAG
if [[ "$KERNEL_GIT_TAG" == *5.10* ]]; then
    KERNEL_VERSION="5.10"
elif [[ "$KERNEL_GIT_TAG" == *6.12* ]]; then
    KERNEL_VERSION="6.12"
elif [[ "$KERNEL_GIT_TAG" == *6.1* ]]; then
    KERNEL_VERSION="6.1"
else
    KERNEL_VERSION=""
fi

BASE_CONFIG="$CONTAINER_REPO_DIR/config/kernel/base_kconfig-${KERNEL_VERSION}"
HWMON_I2C_STUB_CONFIG="$CONTAINER_REPO_DIR/config/kernel/hwmon-i2c-stub.config"

apply_config_fragment() {
    local fragment="$1"
    local line
    local symbol
    local value

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^#\ CONFIG_([A-Za-z0-9_]+)\ is\ not\ set$ ]]; then
            symbol="${BASH_REMATCH[1]}"
            value="n"
        elif [[ "$line" == \#* ]]; then
            continue
        elif [[ "$line" =~ ^CONFIG_([A-Za-z0-9_]+)=(y|m|n)$ ]]; then
            symbol="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
        else
            echo "Error: unsupported config fragment line in $fragment: $line" >&2
            exit 1
        fi

        case "$value" in
            y) ./scripts/config --file "$KERNEL_BUILD_DIR/.config" -e "$symbol" ;;
            m) ./scripts/config --file "$KERNEL_BUILD_DIR/.config" -m "$symbol" ;;
            n) ./scripts/config --file "$KERNEL_BUILD_DIR/.config" -d "$symbol" ;;
        esac
    done < "$fragment"
}

echo "▶ Starting kernel build process (tag=${KERNEL_GIT_TAG}, version=${KERNEL_VERSION})..."

# Clean all?
if [[ "$COMMAND" == "clean" ]]; then
    if [ ! -d "$KERNEL_DIR" ]; then
        echo "Directory $KERNEL_DIR does not exist."
        exit 1
    fi
    echo "Cleaning build directory..."
    make ARCH=x86_64 O="$KERNEL_BUILD_DIR" mrproper -j"$(nproc)"
    exit 0
fi

# Re-init?
if [[ "$COMMAND" == "init" ]]; then
    echo "Re-initializing the kernel directory..."
    rm -rf "$KERNEL_DIR"
fi

git config --global http.sslVerify false

# 1. Clone kernel source
if [ ! -d "$KERNEL_DIR" ]; then
    mkdir -p "$KERNEL_DIR"
    echo "Cloning kernel from $KERNEL_GIT_URL (branch: $KERNEL_GIT_TAG)..."
    git clone --depth=1 --branch="$KERNEL_GIT_TAG" "$KERNEL_GIT_URL" "$KERNEL_DIR"

    if ls "$PATCH_DIR"/*.patch.applied 1> /dev/null 2>&1; then
        rename 's/\.applied$//' "$PATCH_DIR"/*.patch.applied
    fi
else
    echo "Kernel directory $KERNEL_DIR already exists. Skipping clone."
fi

cd "$KERNEL_DIR"

# 2. Apply patches if any exist
if [ -d "$PATCH_DIR" ] && [ -n "$(ls -A "$PATCH_DIR"/*.patch 2>/dev/null)" ]; then
    echo "▶ Applying kernel patches..."
    for patch in "$PATCH_DIR"/*.patch; do
        echo "Applying $(basename "$patch")..."
        git apply "$patch"
        mv "$patch" "$patch".applied
    done
    make ARCH=x86_64 O="$KERNEL_BUILD_DIR" mrproper -j"$(nproc)"
else
    echo "No kernel patches found to apply."
fi

mkdir -p "$KERNEL_BUILD_DIR"

# 3. Configure the kernel
#
# Use the project base config for the detected kernel version when available.
# Falls back to x86_64_defconfig otherwise.
if [ -n "$KERNEL_VERSION" ] && [ -f "$BASE_CONFIG" ]; then
    echo "Using base config for kernel ${KERNEL_VERSION}: $BASE_CONFIG"
    cp "$BASE_CONFIG" "$KERNEL_BUILD_DIR/.config"
else
    echo "Warning: base config not found (version='${KERNEL_VERSION}'). Falling back to x86_64_defconfig."
    make ARCH=x86_64 O="$KERNEL_BUILD_DIR" x86_64_defconfig
fi

# Set local version
./scripts/config --file "$KERNEL_BUILD_DIR/.config" \
    --set-str LOCALVERSION "-${KERNEL_LOCALVERSION}" \
    -d LOCALVERSION_AUTO

# Embed the build configuration in the kernel image (useful for debugging)
./scripts/config --file "$KERNEL_BUILD_DIR/.config" \
    -e IKCONFIG -e IKCONFIG_PROC

# Ensure virtio networking is available (required for QEMU -net nic,model=virtio)
./scripts/config --file "$KERNEL_BUILD_DIR/.config" \
    -e VIRTIO -e VIRTIO_PCI -e VIRTIO_NET

# Enable debugfs and gcov coverage collection when KERNEL_LOCALVERSION contains "gcov"
if [[ "$KERNEL_LOCALVERSION" == *gcov* ]]; then
    echo "▶ Enabling gcov coverage options (DEBUG_FS, GCOV_KERNEL, GCOV_PROFILE_ALL)..."
    ./scripts/config --file "$KERNEL_BUILD_DIR/.config" \
        -e DEBUG_FS \
        -e GCOV_KERNEL \
        -e GCOV_PROFILE_ALL
fi

if [[ -f "$HWMON_I2C_STUB_CONFIG" ]]; then
    echo "▶ Applying hwmon i2c-stub options from $HWMON_I2C_STUB_CONFIG..."
    apply_config_fragment "$HWMON_I2C_STUB_CONFIG"
else
    echo "Warning: hwmon i2c-stub config fragment not found: $HWMON_I2C_STUB_CONFIG"
fi

make ARCH=x86_64 O="$KERNEL_BUILD_DIR" olddefconfig

# 4. Build the kernel
echo "▶ Building kernel bzImage and modules..."
make EXTRA_CFLAGS="-Wno-error" ARCH=x86_64 O="$KERNEL_BUILD_DIR" -j"$(nproc)" bzImage
make EXTRA_CFLAGS="-Wno-error" ARCH=x86_64 O="$KERNEL_BUILD_DIR" -j"$(nproc)" modules

# 5. Archive *.gcno files for coverage report generation on the host.
#    The full build path must be preserved — geninfo relies on the symlinks
#    inside /sys/kernel/debug/gcov/ pointing back to these files.
if [[ "$KERNEL_LOCALVERSION" == *gcov* ]]; then
    GCNO_ARCHIVE="$BASE_DIR/gcov_build-${KERNEL_GIT_TAG}.tar.gz"
    echo "▶ Archiving *.gcno files to $GCNO_ARCHIVE..."
    find "$KERNEL_BUILD_DIR" -name '*.gcno' -print0 \
        | xargs -0 tar czf "$GCNO_ARCHIVE" --absolute-names
    echo "✅ gcno archive: $GCNO_ARCHIVE"
fi

echo "✅ Kernel build finished: $KERNEL_BZIMAGE"
