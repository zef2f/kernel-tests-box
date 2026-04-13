#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Copyright (C) 2025 Vasiliy Kovalev <kovalev@altlinux.org>

set -e
source "$(dirname "$0")/../project.env"
# Sourcing this second to get SSH_KEY_PATH which is set up inside the container
source "$(dirname "$0")/../scripts/01-setup-env.sh" &>/dev/null

help() {
    echo "Usage: $0 [-p PORT] <local_path> <remote_destination>"
    echo ""
    echo "Copies files or directories FROM the host TO the running VM."
    echo ""
    echo "Options:"
    echo "  -p PORT    Specify the VM's SSH port (default: $DEFAULT_VM_SSH_PORT)."
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
shift $((OPTIND -1))

if [ "$#" -ne 2 ]; then
    echo "Error: Invalid number of arguments." >&2
    help
    exit 1
fi

LOCAL_PATH=$1
REMOTE_DEST=$2

echo "▶ Copying '$LOCAL_PATH' to 'root@localhost:${PORT}:$REMOTE_DEST'..."
scp -r -i "$SSH_KEY_PATH" \
    -P "$PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$LOCAL_PATH" \
    "root@localhost:$REMOTE_DEST"

echo "✅ Copied successfully."
