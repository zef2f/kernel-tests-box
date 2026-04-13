#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Copyright (C) 2025 Vasiliy Kovalev <kovalev@altlinux.org>

source "$(dirname "$0")/project.env"

help() {
    echo "Usage: $0 [CONTAINER_NAME]"
    echo "Provides an interactive shell inside the running test container."
    echo "Defaults to CONTAINER_NAME from project.env ('$DEFAULT_CONTAINER_NAME')."
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    help
    exit 0
fi

CONTAINER_NAME=${1:-$DEFAULT_CONTAINER_NAME}

echo "▶ Attaching to container '$CONTAINER_NAME'..."
docker exec -it "$CONTAINER_NAME" /bin/bash
