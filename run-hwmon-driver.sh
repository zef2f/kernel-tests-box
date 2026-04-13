#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# One-command workflow for testing a single hwmon driver:
#   - build or reuse the Docker image
#   - start or reuse the container
#   - clone or reuse hwmon-i2c-stub-tests
#   - build or reuse kernel, QEMU, and guest image
#   - start or reuse the VM
#   - run the driver test and collect artifacts
#
# Usage: $0 [--clean] <driver>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/project.env"

REPO_IN_CONTAINER="/home/user/kernel-tests-box"
HOST_TESTS_DIR="$SCRIPT_DIR/volume/hwmon-i2c-stub-tests"
CONTAINER_TESTS_DIR="/home/user/volume/hwmon-i2c-stub-tests"
HOST_SSH_KEY="$SCRIPT_DIR/volume/image/id_rsa"
LOG_DIR="$SCRIPT_DIR/volume/logs"

CONTAINER_NAME="$DEFAULT_CONTAINER_NAME"
IMAGE_NAME="$DEFAULT_IMAGE_NAME"
STARTED_VM=0
FORCE_REBUILD=0

say() {
    printf '%s\n' "$*"
}

# ---------------------------------------------------------------------------
# show_progress — filter stdin for human-readable build progress
#
# Full output goes to the log file via tee *before* this filter, so nothing
# is lost.  The filter keeps the terminal output concise:
#
#   - Script messages (▶ ✅ --> echo lines)     → pass through
#   - Docker build steps (Step N/M)              → pass through
#   - Git clone / fetch lines                    → pass through
#   - make object lines (CC, LD, AR …)           → aggregate counter
#   - QEMU meson/ninja lines ([N/M])             → aggregate counter
#   - debootstrap I: extraction spam             → first + counter
#   - apt individual package operations          → skip
#   - Errors / warnings                          → always show
# ---------------------------------------------------------------------------
show_progress() {
    awk '
BEGIN { obj = 0; ext = 0 }

# --- always show errors and warnings ---
/[Ee][Rr][Rr][Oo][Rr]/ || /FAIL/ || /fatal:/ { print; fflush(); next }
/[Ww]arning:/ { print; fflush(); next }

# --- kernel / QEMU make: aggregate CC/LD/AR lines ---
/^  (CC|LD|AR|AS|OBJCOPY|HOSTCC|HOSTLD|GEN|CALL|DESCEND|WRAP|CHK|UPD|MODPOST|KSYMS|KSYMTAB|BTF|SYNC|EXPORTS|SHIPPED|VDSO|NM|STRIP|SORTEX|SORTTAB|TEST|INSTALL) / {
    obj++
    if (obj % 500 == 0) { printf "  ... %d objects\n", obj; fflush() }
    next
}
# QEMU ninja-style [123/456] lines
/^\[[0-9]+\/[0-9]+\]/ {
    obj++
    if (obj % 200 == 0) { printf "  ... %d objects\n", obj; fflush() }
    next
}

# --- apt package-level noise ---
/^(Selecting previously|Preparing to unpack|Unpacking |Setting up |Processing triggers)/ { next }
/^(Get:[0-9]|Hit:[0-9]|Ign:[0-9])/ { next }
/^(Reading database|Reading package lists|Building dependency tree)/ { next }

# --- Docker intermediate layer noise ---
/^ ---> [0-9a-f]/ { next }
/^Removing intermediate container/ { next }

# --- debootstrap extraction / unpacking spam ---
/^I: (Extracting |Unpacking )/ { ext++; if (ext == 1) { print; fflush() }; next }
/^I: Validating/ || /^I: Chosen extractor/ || /^I: Checking/ { next }

# --- everything else: show ---
{ print; fflush() }

END {
    if (obj > 0) printf "  ... %d objects — done\n", obj
    if (ext > 1) printf "  ... %d packages extracted\n", ext
}
'
}

fail_step() {
    local label="$1"
    local log_file="$2"

    printf '\nerror: %s failed; see %s\n' "$label" "$log_file" >&2
    if [[ -f "$log_file" ]]; then
        echo "--- last 40 lines of $log_file ---" >&2
        tail -n 40 "$log_file" >&2 || true
    fi
    exit 1
}

run_host_step() {
    local label="$1"
    local log_file="$2"
    shift 2

    say "$label"
    "$@" 2>&1 | tee "$log_file" | show_progress || fail_step "$label" "$log_file"
}

run_docker_step() {
    local label="$1"
    local log_file="$2"
    local command="$3"

    say "$label"
    docker_exec_repo "$command" 2>&1 | tee "$log_file" | show_progress || fail_step "$label" "$log_file"
}

help() {
    echo "Usage: $0 [--clean] <driver>"
    echo ""
    echo "Builds the full hwmon test environment if needed and runs one driver test."
    echo "The hwmon-i2c-stub-tests repository is cloned automatically from:"
    echo "  $HWMON_I2C_STUB_TESTS_GIT_URL"
    echo ""
    echo "Options:"
    echo "  --clean   Force rebuild of Docker image, container, kernel, QEMU, and guest image"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    help
    exit 0
fi

if [[ "${1:-}" == "--clean" ]]; then
    FORCE_REBUILD=1
    shift
fi

if [[ $# -ne 1 ]]; then
    echo "error: driver name is required" >&2
    help >&2
    exit 1
fi

DRIVER="$1"

docker_exec_repo() {
    docker exec "$CONTAINER_NAME" bash -lc "cd '$REPO_IN_CONTAINER' && $1"
}

container_env_test() {
    docker_exec_repo "source ./scripts/01-setup-env.sh >/dev/null && $1" >/dev/null 2>&1
}

vm_process_running() {
    docker exec "$CONTAINER_NAME" pgrep -f qemu-system-x86_64 >/dev/null 2>&1
}

vm_ready() {
    [[ -f "$HOST_SSH_KEY" ]] || return 1

    ssh -i "$HOST_SSH_KEY" \
        -p "$DEFAULT_VM_SSH_PORT" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        root@localhost true >/dev/null 2>&1
}

cleanup() {
    local rc=$?

    if [[ $STARTED_VM -eq 1 ]]; then
        say "vm: stop"
        ssh -i "$HOST_SSH_KEY" \
            -p "$DEFAULT_VM_SSH_PORT" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            root@localhost poweroff >/dev/null 2>&1 || true

        for _ in $(seq 1 30); do
            if ! vm_ready; then
                break
            fi
            sleep 1
        done
    fi

    trap - EXIT INT TERM
    exit "$rc"
}

trap cleanup EXIT INT TERM

if ! command -v docker >/dev/null 2>&1; then
    echo "error: docker not found" >&2
    exit 1
fi

if ! command -v ssh >/dev/null 2>&1; then
    echo "error: ssh not found" >&2
    exit 1
fi

mkdir -p "$LOG_DIR"

"$SCRIPT_DIR/scripts/ensure-hwmon-tests.sh" "$HOST_TESTS_DIR" "$HWMON_I2C_STUB_TESTS_GIT_URL"

if [[ ! -f "$HOST_TESTS_DIR/scripts/${DRIVER}.sh" ]]; then
    echo "error: no test script for driver '$DRIVER'" >&2
    echo "drivers:" >&2
    ls "$HOST_TESTS_DIR/scripts/" 2>/dev/null | sed -n 's/\.sh$//p' | grep -v '^common$' | sed 's/^/  /' >&2
    exit 1
fi

if [[ $FORCE_REBUILD -eq 1 ]]; then
    if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        say "docker-image: remove $IMAGE_NAME"
        docker rmi -f "$IMAGE_NAME" >/dev/null 2>&1 || true
    fi
    if docker ps -aq -f "name=^/${CONTAINER_NAME}$" | grep -q .; then
        say "container: remove $CONTAINER_NAME"
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
fi

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    run_host_step "docker-image: build" "$LOG_DIR/docker-image.log" \
        "$SCRIPT_DIR/build-docker-image.sh" "$IMAGE_NAME"
else
    say "docker-image: reuse $IMAGE_NAME"
fi

"$SCRIPT_DIR/run-container.sh" "$CONTAINER_NAME" "$IMAGE_NAME"

if [[ $FORCE_REBUILD -eq 0 ]] && container_env_test 'test -f "$KERNEL_BZIMAGE"'; then
    say "kernel: reuse"
else
    run_docker_step "kernel: build" "$LOG_DIR/kernel-build.log" \
        "./scripts/02-build-kernel.sh"
fi

if [[ $FORCE_REBUILD -eq 0 ]] && container_env_test '[ "$QEMU_BUILD_DIR" = "$QEMU_SYSTEM_DIR" ] || test -x "$QEMU_BUILD_DIR/usr/bin/qemu-system-x86_64"'; then
    say "qemu: reuse"
else
    run_docker_step "qemu: build" "$LOG_DIR/qemu-build.log" \
        "./scripts/03-build-qemu.sh"
fi

if [[ $FORCE_REBUILD -eq 0 ]] && container_env_test 'test -f "$IMAGE_PATH" && test -f "$SSH_KEY_PATH"'; then
    say "guest-image: reuse"
else
    run_docker_step "guest-image: build" "$LOG_DIR/guest-image-build.log" \
        "./scripts/05-build-image.sh"
fi

if vm_ready; then
    say "vm: reuse"
elif vm_process_running; then
    say "vm: wait"
else
    say "vm: start"
    docker exec -d "$CONTAINER_NAME" bash -lc "cd '$REPO_IN_CONTAINER' && ./scripts/run-vm.sh"
    STARTED_VM=1
fi

say "test: $DRIVER"
docker_exec_repo "./scripts/run-hwmon-tests.sh '$DRIVER' '$CONTAINER_TESTS_DIR'"
