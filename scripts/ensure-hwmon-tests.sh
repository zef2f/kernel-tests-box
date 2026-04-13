#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Ensure that the hwmon i2c-stub test suite exists at the requested path.
#
# Usage: $0 <tests_dir> [git_url]

set -euo pipefail
source "$(dirname "$0")/../project.env"

help() {
    echo "Usage: $0 <tests_dir> [git_url]"
    echo ""
    echo "Clones hwmon-i2c-stub-tests into tests_dir if it is missing."
    echo "If git_url is omitted, HWMON_I2C_STUB_TESTS_GIT_URL from project.env is used."
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    help
    exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Error: invalid number of arguments." >&2
    help >&2
    exit 1
fi

TESTS_DIR="$1"
TESTS_GIT_URL="${2:-$HWMON_I2C_STUB_TESTS_GIT_URL}"

if [[ -d "$TESTS_DIR/.git" ]]; then
    echo "suite: reuse $TESTS_DIR"
    exit 0
fi

if [[ -f "$TESTS_DIR/run-tests.sh" && -d "$TESTS_DIR/scripts" ]]; then
    echo "suite: reuse $TESTS_DIR"
    exit 0
fi

if [[ -e "$TESTS_DIR" && ! -d "$TESTS_DIR" ]]; then
    echo "Error: destination exists and is not a directory: $TESTS_DIR" >&2
    exit 1
fi

if [[ -d "$TESTS_DIR" ]] && find "$TESTS_DIR" -mindepth 1 -print -quit | grep -q .; then
    echo "Error: directory exists but does not look like hwmon-i2c-stub-tests: $TESTS_DIR" >&2
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "Error: git is required to clone $TESTS_GIT_URL" >&2
    exit 1
fi

mkdir -p "$(dirname "$TESTS_DIR")"

echo "suite: clone $TESTS_DIR"
git clone --depth=1 "$TESTS_GIT_URL" "$TESTS_DIR"
echo "suite: ok $TESTS_DIR"
