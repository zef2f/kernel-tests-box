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
    echo "Clones, patches, configures, and builds the qemu (all by default)."
    echo ""
    echo "Commands:"
    echo "  clean         Clean all."
    echo "  init          Re-initializing the qemu directory and applying patches, if any."
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message."
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    help
    exit 0
fi

COMMAND=$1

PATCH_DIR="$CONTAINER_REPO_DIR/patches/qemu"

echo "▶ Starting QEMU build..."

# Check qemu path
if [[ "$QEMU_BUILD_DIR" == "$QEMU_SYSTEM_DIR" ]]; then
    sudo apt-get update && \
    sudo apt-get install -y qemu
    echo "System QEMU is used. Skipping build."
    exit 0
fi

# Clean all ?
if [ -d "$QEMU_BUILD_DIR" ] && [[ "$COMMAND" == "clean" ]]; then
    echo "Clean all"
    pushd "$QEMU_BUILD_DIR"
    make clean -j`nproc`
    popd
    exit 0
fi

# Re-init ?
if [[ "$COMMAND" == "init" ]]; then
    echo "Re-initializing the QEMU directory"
    rm -rf "$QEMU_DIR"
fi

if [ ! -d "$QEMU_DIR" ]; then
    mkdir -p "$QEMU_DIR"
    echo "Cloning QEMU from $QEMU_GIT_URL..."
    git clone --depth=1 --branch="$QEMU_GIT_TAG" "$QEMU_GIT_URL" "$QEMU_DIR"

    if ls "$PATCH_DIR"/*.patch.applied 1> /dev/null 2>&1; then
        rename 's/\.applied$//' "$PATCH_DIR"/*.patch.applied
    fi
else
    echo "QEMU directory $QEMU_DIR already exists. Skipping clone."
fi

cd "$QEMU_DIR"

# Apply patches if any exist
if [ -d "$PATCH_DIR" ] && [ -n "$(ls -A $PATCH_DIR/*.patch 2>/dev/null)" ]; then
    echo "▶ Applying QEMU patches..."
    for patch in $PATCH_DIR/*.patch; do
        echo "Applying $(basename $patch)..."
        git apply "$patch"
        mv "$patch" "$patch".applied
    done
else
    echo "No QEMU patches found to apply."
fi

# BuildRequires should be installed
# See qemu.spec (alt gear repo http://git.altlinux.org/gears/q/qemu.git)
# All list `gear --verbose --commit --rpmbuild  -- rpmbuild -bc`

# Build
mkdir -p "$QEMU_BUILD_DIR"
cd "$QEMU_BUILD_DIR"

../configure				\
    --prefix="${QEMU_BUILD_DIR}"/usr	\
    --target-list=x86_64-softmmu	\
    --disable-xkbcommon			\
    --disable-gtk			\
    --disable-libssh			\
    --disable-werror			\
    --disable-docs			\
    --disable-xen			\
    --disable-libnfs			\
    --enable-debug			\
    --enable-virtfs			\
    --enable-slirp

make -j"$(nproc)"
make install

echo "✅ QEMU build finished successfully."
