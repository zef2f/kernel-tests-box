#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Push a local directory into a destination directory on the VM.
# Uses tar|ssh instead of scp -r to handle broken symlinks (e.g. .git/hooks).
#
# Run inside the container (needs SSH_KEY_PATH from 01-setup-env.sh).
#
# Usage: $0 [-p PORT] [-x PATTERN] <local_dir> <remote_dest>
#   local_dir    Local directory to push.
#   remote_dest  Parent directory on the VM — local_dir is placed inside it.
#
# Options:
#   -p PORT      VM SSH port (default: $DEFAULT_VM_SSH_PORT).
#   -x PATTERN   Additional tar --exclude pattern (repeatable).
#   -h           Show this help.

set -euo pipefail
source "$(dirname "$0")/../project.env"
source "$(dirname "$0")/01-setup-env.sh" &>/dev/null

help() {
    echo "Usage: $0 [-p PORT] [-x PATTERN] <local_dir> <remote_dest>"
    echo ""
    echo "Pushes LOCAL_DIR into REMOTE_DEST/ on the VM via tar|ssh."
    echo ".git is excluded automatically."
    echo ""
    echo "Options:"
    echo "  -p PORT      VM SSH port (default: $DEFAULT_VM_SSH_PORT)."
    echo "  -x PATTERN   Additional tar --exclude pattern (repeatable)."
    echo "  -h           Show this help."
}

PORT=$DEFAULT_VM_SSH_PORT
EXCLUDES=(--exclude='.git')

while getopts "hp:x:" opt; do
    case $opt in
        h) help; exit 0 ;;
        p) PORT=$OPTARG ;;
        x) EXCLUDES+=(--exclude="$OPTARG") ;;
        \?) echo "Invalid option: -$OPTARG" >&2; help; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [[ $# -ne 2 ]]; then
    echo "Error: expected 2 arguments, got $#." >&2
    help; exit 1
fi

LOCAL_DIR="$1"
REMOTE_DEST="$2"

if [[ ! -d "$LOCAL_DIR" ]]; then
    echo "Error: '$LOCAL_DIR' is not a directory." >&2
    exit 1
fi

SSH_OPTS=(-i "$SSH_KEY_PATH" -p "$PORT"
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

echo "▶ Pushing '$(basename "$LOCAL_DIR")' → VM:$REMOTE_DEST ..."
ssh "${SSH_OPTS[@]}" root@localhost "mkdir -p '$REMOTE_DEST'"
tar -C "$(dirname "$(realpath "$LOCAL_DIR")")" "${EXCLUDES[@]}" -czf - "$(basename "$LOCAL_DIR")" \
    | ssh "${SSH_OPTS[@]}" root@localhost "tar -xzf - -C '$REMOTE_DEST'"
echo "✅ Pushed: $(basename "$LOCAL_DIR") → VM:$REMOTE_DEST"
