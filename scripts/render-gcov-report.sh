#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Generates an LCOV HTML coverage report from gcov data collected in the VM.
#
# Prerequisites (on the host / inside the container):
#   - gcov_data.tar   transferred from the VM via scp-from-vm.sh
#   - gcov_build-*.tar.gz   produced by 02-build-kernel.sh after a gcov build
#     (*.gcno files must be restored to the same absolute paths as during build)
#
# Usage: $0 <gcov_data.tar> <report_title>

set -euo pipefail
source "$(dirname "$0")/01-setup-env.sh"

help() {
    echo "Usage: $0 <gcov_data.tar> <report_title>"
    echo ""
    echo "Arguments:"
    echo "  gcov_data.tar   Archive of /sys/kernel/debug/gcov/ from the VM"
    echo "                  (produced by collect-gcov-in-vm.sh)."
    echo "  report_title    Title string for the HTML report."
    echo ""
    echo "Environment:"
    echo "  GCOV            gcov binary to use (default from 01-setup-env.sh: $GCOV)."
    echo "                  Must match the GCC version used to build the kernel."
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    help
    exit 0
fi

if [[ "$#" -ne 2 ]]; then
    echo "Error: invalid number of arguments." >&2
    help
    exit 1
fi

GCOV_DATA_TAR="$(readlink -f "$1")"
REPORT_TITLE="$2"

if [[ ! -f "$GCOV_DATA_TAR" ]]; then
    echo "Error: file not found: $GCOV_DATA_TAR" >&2
    exit 1
fi

LABEL="$(basename "$GCOV_DATA_TAR" .tar)"
GCDA_PATH="$BASE_DIR/gcda-${LABEL}"
GCOV_INFO="$BASE_DIR/coverage.${LABEL}.info"
REPORT_DIR="$BASE_DIR/report-${LABEL}"

rm -rf "$GCDA_PATH" "$REPORT_DIR"
rm -f "$GCOV_INFO"
mkdir -p "$GCDA_PATH"

tar xf "$GCOV_DATA_TAR" -C "$GCDA_PATH"

# -f: follow symlinks (the gcov/ snapshot uses symlinks back to *.gcno in the build tree)
geninfo --quiet --gcov-tool="$GCOV" -f -o "$GCOV_INFO" "$GCDA_PATH"

genhtml --quiet -t "$REPORT_TITLE" -o "$REPORT_DIR" "$GCOV_INFO"

lcov --summary "$GCOV_INFO"
