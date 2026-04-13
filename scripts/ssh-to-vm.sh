#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Copyright (C) 2025 Vasiliy Kovalev <kovalev@altlinux.org>

set -e
source "$(dirname "$0")/../project.env"
source "$(dirname "$0")/01-setup-env.sh" &>/dev/null

help() {
    echo "Usage: $0 [-p PORT]"
    echo ""
    echo "Connects to the running VM via SSH."
    echo ""
    echo "Options:"
    echo "  -p PORT    VM SSH port on the host (default: $DEFAULT_VM_SSH_PORT)."
    echo "  -h         Show this help message."
}

PORT=$DEFAULT_VM_SSH_PORT
while getopts "hp:" opt; do
    case ${opt} in
        h) help; exit 0 ;;
        p) PORT=$OPTARG ;;
        \?) echo "Invalid option -$OPTARG" >&2; help; exit 1 ;;
    esac
done

echo "▶ Connecting to VM via SSH on port $PORT..."
echo "  Hint: mount debugfs with: mount -t debugfs none /sys/kernel/debug"

ssh -i "$SSH_KEY_PATH" \
    -p "$PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@localhost
