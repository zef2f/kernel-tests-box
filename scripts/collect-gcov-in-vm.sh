#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Run this script INSIDE the VM after test execution to collect gcov coverage data.
# Copy it to the VM with scp-to-vm.sh, then execute as root.
#
# Usage: ./collect-gcov-in-vm.sh [output_dir]
#   output_dir  Directory where gcov_data.tar will be written (default: /root)

set -euo pipefail

OUTPUT_DIR="${1:-/root}"
GCOV_DIR="/sys/kernel/debug/gcov"
TMP_DIR=""

cleanup() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

# Mount debugfs if not already mounted
if ! mountpoint -q /sys/kernel/debug; then
    mount -t debugfs none /sys/kernel/debug
fi

if [[ ! -d "$GCOV_DIR" ]]; then
    echo "Error: $GCOV_DIR does not exist." >&2
    echo "Make sure the kernel was built with CONFIG_GCOV_KERNEL=y and CONFIG_DEBUG_FS=y." >&2
    exit 1
fi

TMP_DIR="$(mktemp -d)"

echo "Collecting gcov data from $GCOV_DIR..."
find "$GCOV_DIR" -type d -exec mkdir -p "$TMP_DIR"/{} \;
find "$GCOV_DIR" -name '*.gcda' -exec sh -c 'cat < "$1" > "$2/$1"' _ {} "$TMP_DIR" \;
find "$GCOV_DIR" -name '*.gcno' -exec sh -c 'cp -d "$1" "$2/$1"' _ {} "$TMP_DIR" \;

cd "$OUTPUT_DIR"
tar -cf ./gcov_data.tar -C "$TMP_DIR" sys
