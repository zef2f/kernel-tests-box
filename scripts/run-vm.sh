#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Copyright (C) 2025 Vasiliy Kovalev <kovalev@altlinux.org>

set -eo pipefail
source "$(dirname "$0")/01-setup-env.sh"
source "$(dirname "$0")/../project.env"

help() {
    echo "Usage: $0 [-p PORT] [-m MB] [-s SMP] [-a 'extra kernel args']"
    echo ""
    echo "Starts a QEMU VM for functional testing."
    echo ""
    echo "Options:"
    echo "  -p PORT    Host port forwarded to VM SSH port 22 (default: $DEFAULT_VM_SSH_PORT)."
    echo "  -m MB      VM RAM in MB (default: 4096)."
    echo "  -s SMP     Number of virtual CPUs (default: 2)."
    echo "  -a ARGS    Extra kernel command line arguments."
    echo "  -h         Show this help message."
}

PORT=$DEFAULT_VM_SSH_PORT
MEM=4096
SMP=2
EXTRA_APPEND=""

while getopts "hp:m:s:a:" opt; do
    case ${opt} in
        h) help; exit 0 ;;
        p) PORT=$OPTARG ;;
        m) MEM=$OPTARG ;;
        s) SMP=$OPTARG ;;
        a) EXTRA_APPEND=$OPTARG ;;
        \?) echo "Invalid option -$OPTARG" >&2; help; exit 1 ;;
    esac
done

if [ ! -f "$KERNEL_BZIMAGE" ]; then
    echo "Error: kernel image not found at $KERNEL_BZIMAGE" >&2
    echo "Run 02-build-kernel.sh first." >&2
    exit 1
fi

if [ ! -f "$IMAGE_PATH" ]; then
    echo "Error: root filesystem image not found at $IMAGE_PATH" >&2
    echo "Run 05-build-image.sh first." >&2
    exit 1
fi

# Resolve QEMU binary: use the built-from-source binary, or system binary if configured
if [ -n "$QEMU_BUILD_DIR" ] && [ "$QEMU_BUILD_DIR" != "$QEMU_SYSTEM_DIR" ]; then
    QEMU_BIN="$QEMU_BUILD_DIR/usr/bin/qemu-system-x86_64"
else
    QEMU_BIN="qemu-system-x86_64"
fi

echo "▶ Starting QEMU VM..."
echo "  kernel:  $KERNEL_BZIMAGE"
echo "  rootfs:  $IMAGE_PATH"
echo "  SSH:     localhost:$PORT"

rm -f "$DEBUG_VM_LOG_FILE"

# Base QEMU invocation for the test VM.
# hostfwd is added to -net user for SSH access (scp-to-vm.sh / scp-from-vm.sh).
script -q -c "
$QEMU_BIN \
    -cpu host -enable-kvm -m $MEM -smp $SMP -nographic \
    -kernel '$KERNEL_BZIMAGE' \
    -append 'console=ttyS0 root=/dev/sda earlyprintk=serial net.ifnames=0 console_msg_format=syslog $EXTRA_APPEND' \
    -drive file='$IMAGE_PATH',format=raw \
    -net nic,model=virtio,macaddr=52:54:00:12:34:58 \
    -net user,hostfwd=tcp::${PORT}-:22 \
    -monitor none
" "$DEBUG_VM_LOG_FILE"

echo "VM has been shut down. Log: $DEBUG_VM_LOG_FILE"
