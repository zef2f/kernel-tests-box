#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Copyright (C) 2025 Vasiliy Kovalev <kovalev@altlinux.org>

set -e
source "$(dirname "$0")/project.env"

help() {
    echo "Usage: $0 [CONTAINER_NAME] [IMAGE_NAME]"
    echo ""
    echo "Runs the Docker container in detached mode."
    echo "Arguments are optional and default to values from project.env."
    echo "  - CONTAINER_NAME: '${DEFAULT_CONTAINER_NAME}'"
    echo "  - IMAGE_NAME:     '${DEFAULT_IMAGE_NAME}'"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message."
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    help
    exit 0
fi

CONTAINER_NAME=${1:-$DEFAULT_CONTAINER_NAME}
IMAGE_NAME=${2:-$DEFAULT_IMAGE_NAME}
REPO_DIR="$(pwd)"
CONTAINER_ID="$(docker ps -aq -f "name=^/${CONTAINER_NAME}$")"

if [ "$(docker ps -q -f "name=^/${CONTAINER_NAME}$")" ]; then
    echo "container: reuse $CONTAINER_NAME"
    exit 0
fi

if [ -n "$CONTAINER_ID" ]; then
    echo "container: drop $CONTAINER_NAME"
    docker rm -f "$CONTAINER_NAME"
fi

if [ ! -d "$REPO_DIR/volume" ]; then
    echo "volume: create $REPO_DIR/volume"
    mkdir "$REPO_DIR/volume"
fi

echo "container: start $CONTAINER_NAME"
docker run -d \
    --name "$CONTAINER_NAME" \
    --privileged \
    --group-add "$(stat -c "%g" /dev/kvm)" \
    -p "${DEFAULT_VM_SSH_PORT}:${DEFAULT_VM_SSH_PORT}" \
    -v "$REPO_DIR:/home/user/kernel-tests-box:Z" \
    -v "$REPO_DIR/volume:/home/user/volume:Z" \
    "$IMAGE_NAME" \
    tail -f /dev/null

echo "container: ok $CONTAINER_NAME"
