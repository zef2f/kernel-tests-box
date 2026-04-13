#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Run hwmon-i2c-stub-tests for a single driver in the VM, collect all artifacts
# required for a coverage report:
#
#   1. <label>-kernel.config     — full config of the running VM kernel
#   2. <label>-kernel-log.txt    — kernel ring buffer (dmesg) during the test
#   3. <label>-test-stdout.txt   — test stdout/stderr
#   4. <label>-gcov.info         — LCOV tracefile
#   5. <label>-gcov-html.tar.gz  — HTML coverage report (archived)
#
# In addition, reports line/function coverage specifically for
# drivers/hwmon/<driver>.c.
#
# Run inside the container (or via docker exec).
# If TESTS_DIR does not exist, it is cloned automatically from
# $HWMON_I2C_STUB_TESTS_GIT_URL.
#
# Usage: $0 <driver> [TESTS_DIR]
#   driver      Name of the hwmon driver to test (e.g. lm90, adm1031).
#               A corresponding test script must exist at
#               TESTS_DIR/scripts/<driver>.sh.
#   TESTS_DIR   Path to hwmon-i2c-stub-tests (default: $BASE_DIR/hwmon-i2c-stub-tests).

set -euo pipefail
source "$(dirname "$0")/01-setup-env.sh"
source "$(dirname "$0")/../project.env"

say() {
    printf '%s\n' "$*"
}

help() {
    sed -n '3,/^set /p' "$0" | sed -n 's/^# \{0,1\}//p' | sed '$d'
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    help
    exit 0
fi

if [[ $# -lt 1 ]]; then
    echo "error: driver name is required" >&2
    echo "" >&2
    help >&2
    exit 1
fi

DRIVER="$1"
TESTS_DIR="${2:-$BASE_DIR/hwmon-i2c-stub-tests}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REMOTE_TESTS="/root/$(basename "$TESTS_DIR")"

if [[ ! -d "$TESTS_DIR" ]]; then
    "$SCRIPT_DIR/ensure-hwmon-tests.sh" "$TESTS_DIR"
fi

if [[ ! -f "$TESTS_DIR/scripts/${DRIVER}.sh" ]]; then
    echo "error: no test script for driver '$DRIVER'" >&2
    echo "drivers:" >&2
    ls "$TESTS_DIR/scripts/" 2>/dev/null | sed -n 's/\.sh$//p' | grep -v '^common$' | sed 's/^/  /' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Artifact paths
# ---------------------------------------------------------------------------

LABEL="${KERNEL_GIT_TAG}-hwmon-${DRIVER}"
ARTIFACTS_DIR="$BASE_DIR/artifacts/${LABEL}"
mkdir -p "$ARTIFACTS_DIR"

KERNEL_LOG="${ARTIFACTS_DIR}/${LABEL}-kernel-log.txt"
KERNEL_CONFIG="${ARTIFACTS_DIR}/${LABEL}-kernel.config"
TEST_STDOUT="${ARTIFACTS_DIR}/${LABEL}-test-stdout.txt"
GCOV_INFO_OUT="${ARTIFACTS_DIR}/${LABEL}-gcov.info"
GCOV_HTML_TGZ="${ARTIFACTS_DIR}/${LABEL}-gcov-html.tar.gz"
DRIVER_INFO="${ARTIFACTS_DIR}/${LABEL}-driver.info"

# Intermediate files in $BASE_DIR (reused by render-gcov-report.sh)
GCOV_TAR_LABEL="gcov_data.hwmon-${DRIVER}"
GCOV_TAR="${BASE_DIR}/${GCOV_TAR_LABEL}.tar"
RENDERED_REPORT_DIR="${BASE_DIR}/report-${GCOV_TAR_LABEL}"
RENDERED_INFO="${BASE_DIR}/coverage.${GCOV_TAR_LABEL}.info"

# ---------------------------------------------------------------------------
# SSH helpers
# ---------------------------------------------------------------------------

SSH_OPTS=(-q -i "$SSH_KEY_PATH" -p "$DEFAULT_VM_SSH_PORT"
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

ssh_vm() { ssh "${SSH_OPTS[@]}" root@localhost "$@"; }

# ---------------------------------------------------------------------------
# Wait for VM
# ---------------------------------------------------------------------------

say "vm: wait-ssh"
for i in $(seq 1 60); do
    if ssh_vm true 2>/dev/null; then
        say "vm: ready"
        break
    fi
    sleep 5
    [[ $i -eq 60 ]] && { echo "error: vm ssh timeout" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# Save the full config of the running VM kernel
# ---------------------------------------------------------------------------

say "config: save"
if ! ssh_vm 'if [ -r /proc/config.gz ]; then zcat /proc/config.gz; elif [ -r "/boot/config-$(uname -r)" ]; then cat "/boot/config-$(uname -r)"; else exit 1; fi' > "$KERNEL_CONFIG"; then
    echo "warn: failed to save running kernel config" >&2
    rm -f "$KERNEL_CONFIG"
fi

# ---------------------------------------------------------------------------
# Push test suite and gcov helper to VM
# ---------------------------------------------------------------------------

ssh_vm "rm -rf '$REMOTE_TESTS'"
"$SCRIPT_DIR/vm-push-dir.sh" "$TESTS_DIR" "/root" >/dev/null

scp -q -i "$SSH_KEY_PATH" -P "$DEFAULT_VM_SSH_PORT" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SCRIPT_DIR/collect-gcov-in-vm.sh" "root@localhost:/root/collect-gcov-in-vm.sh"

# ---------------------------------------------------------------------------
# Reset gcov counters and kernel ring buffer for a clean per-driver run
# ---------------------------------------------------------------------------

say "gcov: reset"
ssh_vm "mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug"
ssh_vm "echo 0 > /sys/kernel/debug/gcov/reset" \
    || { echo "error: failed to reset gcov counters" >&2; exit 1; }
ssh_vm "dmesg -C"

# ---------------------------------------------------------------------------
# Run the driver test; capture stdout+stderr to file
# ---------------------------------------------------------------------------

say "driver: $DRIVER"

set +e
ssh_vm "cd '$REMOTE_TESTS' && bash run-tests.sh '$DRIVER' 2>&1" >"$TEST_STDOUT"
TEST_EXIT=$?
set -e

# ---------------------------------------------------------------------------
# Capture dmesg ring buffer
# ---------------------------------------------------------------------------

say "dmesg: save"
ssh_vm "dmesg" > "$KERNEL_LOG"

# ---------------------------------------------------------------------------
# Collect gcov data from VM
# ---------------------------------------------------------------------------

say "gcov: collect"
ssh_vm "bash /root/collect-gcov-in-vm.sh >/dev/null"

scp -q -i "$SSH_KEY_PATH" -P "$DEFAULT_VM_SSH_PORT" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "root@localhost:/root/gcov_data.tar" "$GCOV_TAR"

# ---------------------------------------------------------------------------
# Generate LCOV tracefile + HTML report
# ---------------------------------------------------------------------------

say "gcov: report"
"$SCRIPT_DIR/render-gcov-report.sh" "$GCOV_TAR" "hwmon ${DRIVER} (${KERNEL_GIT_TAG})"

cp "$RENDERED_INFO" "$GCOV_INFO_OUT"

say "report: archive"
tar -C "$BASE_DIR" -czf "$GCOV_HTML_TGZ" "report-${GCOV_TAR_LABEL}"

# ---------------------------------------------------------------------------
# Per-driver coverage summary for drivers/hwmon/<driver>.c
# ---------------------------------------------------------------------------

DRIVER_FILE="drivers/hwmon/${DRIVER}.c"
say "cover: ${DRIVER_FILE}"

if lcov --quiet --extract "$GCOV_INFO_OUT" "*/${DRIVER_FILE}" -o "$DRIVER_INFO" 2>/dev/null \
   && [[ -s "$DRIVER_INFO" ]]; then
    lcov --summary "$DRIVER_INFO" 2>&1 | grep -E '^\s*(lines|functions|branches)'
else
    echo "warn: no coverage data for ${DRIVER_FILE}" >&2
    rm -f "$DRIVER_INFO"
fi

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------

say "artifacts: $ARTIFACTS_DIR"

if [[ $TEST_EXIT -eq 0 ]]; then
    say "status: ok"
else
    echo "status: fail ($TEST_EXIT)" >&2
fi

exit $TEST_EXIT
