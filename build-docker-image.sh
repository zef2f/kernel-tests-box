#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Copyright (C) 2025 Vasiliy Kovalev <kovalev@altlinux.org>

set -e
source "$(dirname "$0")/project.env"

help() {
    echo "Usage: $0 [IMAGE_NAME]"
    echo ""
    echo "Builds the Docker image for kernel-tests-box."
    echo "If IMAGE_NAME is not provided, uses DEFAULT_IMAGE_NAME from project.env ('$DEFAULT_IMAGE_NAME')."
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message."
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    help
    exit 0
fi

IMAGE_NAME=${1:-$DEFAULT_IMAGE_NAME}

echo "docker-image: build $IMAGE_NAME"

docker build -t "$IMAGE_NAME" \
    --build-arg UID=$(id -u) \
    --build-arg GID=$(id -g) \
    .

echo "docker-image: ok $IMAGE_NAME"
