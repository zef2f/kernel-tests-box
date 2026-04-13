#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Generate golden (expected) output files for a test suite.
# Runs the suite's generate-golden.sh inside the VM, then copies the
# result.outs/ directories back to the host.
#
# Only processes tests that are missing result.outs/out.1 on the host.
# Re-runs all if --force is given.
#
# Run inside the container (or via docker exec).
# If TESTS_DIR does not exist, it is cloned automatically from
# $HWMON_I2C_STUB_TESTS_GIT_URL.
#
# Usage: $0 [--force] [TESTS_DIR]
#   TESTS_DIR  Path to the test suite (default: $BASE_DIR/hwmon-i2c-stub-tests).
#              Must contain tests/list.txt and generate-golden.sh.

set -euo pipefail
source "$(dirname "$0")/01-setup-env.sh"
source "$(dirname "$0")/../project.env"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

FORCE=0
TESTS_DIR=""

for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        -*) echo "Unknown option: $arg" >&2; exit 1 ;;
        *)  TESTS_DIR="$arg" ;;
    esac
done

TESTS_DIR="${TESTS_DIR:-$BASE_DIR/hwmon-i2c-stub-tests}"

# ---------------------------------------------------------------------------

if [[ ! -d "$TESTS_DIR" ]]; then
    "$SCRIPT_DIR/ensure-hwmon-tests.sh" "$TESTS_DIR"
fi

if [[ ! -f "$TESTS_DIR/tests/list.txt" ]]; then
    echo "Error: $TESTS_DIR/tests/list.txt not found." >&2
    exit 1
fi

if [[ ! -f "$TESTS_DIR/generate-golden.sh" ]]; then
    echo "Error: $TESTS_DIR/generate-golden.sh not found." >&2
    exit 1
fi

# Check which tests are missing golden files
missing=()
while IFS= read -r test_name; do
    [[ -z "$test_name" || "$test_name" == \#* ]] && continue
    if [[ $FORCE -eq 1 || ! -f "$TESTS_DIR/tests/$test_name/result.outs/out.1" ]]; then
        missing+=("$test_name")
    fi
done < "$TESTS_DIR/tests/list.txt"

if [[ ${#missing[@]} -eq 0 ]]; then
    echo "✅ All golden files are already present. Use --force to regenerate."
    exit 0
fi

echo "▶ Tests missing golden files: ${missing[*]}"

# Push test suite to VM
REMOTE_TESTS="/root/$(basename "$TESTS_DIR")"
"$SCRIPT_DIR/vm-push-dir.sh" "$TESTS_DIR" "/root"

# Run generate-golden.sh inside the VM
SSH_OPTS=(-i "$SSH_KEY_PATH" -p "$DEFAULT_VM_SSH_PORT"
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

echo "▶ Running generate-golden.sh in the VM..."
ssh "${SSH_OPTS[@]}" root@localhost "cd '$REMOTE_TESTS' && bash generate-golden.sh"

# Pull result.outs back for tests that were missing
echo "▶ Copying golden files back to host..."
for test_name in "${missing[@]}"; do
    remote_outs="$REMOTE_TESTS/tests/$test_name/result.outs"
    local_test_dir="$TESTS_DIR/tests/$test_name"

    if ssh "${SSH_OPTS[@]}" root@localhost "test -f '$remote_outs/out.1'" 2>/dev/null; then
        "$SCRIPT_DIR/vm-pull-dir.sh" "$remote_outs" "$local_test_dir"
    else
        echo "  Warning: $test_name — no result.outs/out.1 produced (test skipped or failed)."
    fi
done

echo "✅ Golden file generation complete."
