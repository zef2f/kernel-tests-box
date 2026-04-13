#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Copyright (C) 2025 Vasiliy Kovalev <kovalev@altlinux.org>

set -eo pipefail
source "$(dirname "$0")/project.env"

help() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Main control script for kernel-tests-box."
    echo ""
    echo "Commands:"
    echo "  build       Build the Docker image."
    echo "  container   Start the Docker container."
    echo "  kernel      Build the kernel (inside the container)."
    echo "  qemu        Build QEMU from source (inside the container)."
    echo "  image       Build the Debian 11 guest root filesystem (inside the container)."
    echo "  setup       Run all setup steps: kernel, qemu, image."
    echo "  all         Run all stages: build, container, setup (default)."
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message."
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    help
    exit 0
fi

COMMAND=${1:-all}
CONTAINER_NAME=$DEFAULT_CONTAINER_NAME

run_build() {
    echo "▶ (build) Building Docker image..."
    ./build-docker-image.sh
}

run_container() {
    if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
        echo "ℹ️ (container) Container '$CONTAINER_NAME' is already running. Skipping."
    else
        echo "▶ (container) Starting Docker container..."
        ./run-container.sh
    fi
}

exec_in_container() {
    local name="$1"
    local script="$2"
    echo "▶ ($name) Executing $script inside container..."
    docker exec "$CONTAINER_NAME" "./scripts/$script"
}

case "$COMMAND" in
    build)
        run_build
        ;;
    container)
        run_container
        ;;
    kernel)
        run_container
        exec_in_container "kernel" "02-build-kernel.sh"
        ;;
    qemu)
        run_container
        exec_in_container "qemu" "03-build-qemu.sh"
        ;;
    image)
        run_container
        exec_in_container "image" "05-build-image.sh"
        ;;
    setup)
        run_container
        exec_in_container "kernel" "02-build-kernel.sh"
        exec_in_container "qemu"   "03-build-qemu.sh"
        exec_in_container "image"  "05-build-image.sh"
        ;;
    all)
        run_build
        run_container
        exec_in_container "kernel" "02-build-kernel.sh"
        exec_in_container "qemu"   "03-build-qemu.sh"
        exec_in_container "image"  "05-build-image.sh"
        ;;
    *)
        echo "Error: Unknown command '$COMMAND'"
        help
        exit 1
        ;;
esac

echo "✅ Command '$COMMAND' finished."
