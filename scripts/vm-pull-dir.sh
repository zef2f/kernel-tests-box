#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Pull a directory from the VM into a local destination directory.
# Uses ssh|tar instead of scp -r to handle broken symlinks.
#
# Run inside the container (needs SSH_KEY_PATH from 01-setup-env.sh).
#
# Usage: $0 [-p PORT] <remote_dir> <local_dest>
#   remote_dir   Directory on the VM to pull.
#   local_dest   Local parent directory — remote_dir is placed inside it.
#
# Options:
#   -p PORT   VM SSH port (default: $DEFAULT_VM_SSH_PORT).
#   -h        Show this help.

set -euo pipefail
source "$(dirname "$0")/../project.env"
source "$(dirname "$0")/01-setup-env.sh" &>/dev/null

help() {
    echo "Usage: $0 [-p PORT] <remote_dir> <local_dest>"
    echo ""
    echo "Pulls REMOTE_DIR from the VM into LOCAL_DEST/ via ssh|tar."
    echo ""
    echo "Options:"
    echo "  -p PORT   VM SSH port (default: $DEFAULT_VM_SSH_PORT)."
    echo "  -h        Show this help."
}

PORT=$DEFAULT_VM_SSH_PORT

while getopts "hp:" opt; do
    case $opt in
        h) help; exit 0 ;;
        p) PORT=$OPTARG ;;
        \?) echo "Invalid option: -$OPTARG" >&2; help; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [[ $# -ne 2 ]]; then
    echo "Error: expected 2 arguments, got $#." >&2
    help; exit 1
fi

REMOTE_DIR="$1"
LOCAL_DEST="$2"

SSH_OPTS=(-i "$SSH_KEY_PATH" -p "$PORT"
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

mkdir -p "$LOCAL_DEST"
echo "▶ Pulling VM:$REMOTE_DIR → '$LOCAL_DEST' ..."
ssh "${SSH_OPTS[@]}" root@localhost \
    "tar -czf - -C '$(dirname "$REMOTE_DIR")' '$(basename "$REMOTE_DIR")'" \
    | tar -xzf - -C "$LOCAL_DEST"
echo "✅ Pulled: VM:$REMOTE_DIR → $LOCAL_DEST"
