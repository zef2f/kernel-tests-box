#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Copyright (C) 2025 Vasiliy Kovalev <kovalev@altlinux.org>

# --- Environment Setup Script ---
# Defines all environment variables for the kernel test environment.
# Modify the variables in the "User Configuration" section to fit your needs.

# --- ⚙️ User Configuration ---
export TERM="xterm-256color"

# Kernel local version suffix.
# Include "gcov" to enable coverage collection (GCOV_KERNEL, GCOV_PROFILE_ALL).
# Example: "kernel-tests-gcov" enables coverage; "kernel-tests" disables it.
export KERNEL_LOCALVERSION="kernel-tests-gcov"

# Container repo directory (path inside the container)
export CONTAINER_REPO_DIR="/home/user/kernel-tests-box"

# ------------------------

# Kernel git repository URL and tag/branch.
# Supported versions: 5.10, 6.1, 6.12.
export KERNEL_GIT_URL="https://git.linuxtesting.ru/pub/scm/linux/kernel/git/lvc/linux-stable.git"
export KERNEL_GIT_TAG="linux-6.12-lvc"
# export KERNEL_GIT_TAG="linux-6.1-lvc"
# export KERNEL_GIT_TAG="linux-5.10-lvc"
# Pinned releases:
# export KERNEL_GIT_TAG="v6.12.77-lvc16"
# export KERNEL_GIT_TAG="v6.1.166-lvc48"
# export KERNEL_GIT_TAG="v5.10.252-lvc76"

# ------------------------

# QEMU repository (built from source inside the container).
# The methodology references QEMU 7.2.11, so use that version by default.
# Set QEMU_BUILD_DIR=QEMU_SYSTEM_DIR below to use the system-installed QEMU instead.
export QEMU_GIT_URL="https://github.com/qemu/qemu.git"
export QEMU_GIT_TAG="v7.2.11"

# ------------------------

# --- 🛠️ Core Variables (usually no need to change) ---

# Base directory for all operations inside the container
export BASE_DIR=~/volume

# Kernel paths
export KERNEL_DIR="$BASE_DIR/linux-${KERNEL_GIT_TAG}"
export KERNEL_BUILD_DIR="$KERNEL_DIR/build"
export KERNEL_BZIMAGE="$KERNEL_BUILD_DIR/arch/x86/boot/bzImage"

# QEMU paths
export QEMU_DIR="$BASE_DIR/qemu-${QEMU_GIT_TAG}"
export QEMU_BUILD_DIR="$QEMU_DIR/build"
export QEMU_SYSTEM_DIR=""
# To use the system QEMU binary (/usr/bin/qemu-system-x86_64), uncomment:
# export QEMU_BUILD_DIR="$QEMU_SYSTEM_DIR"

# Guest Image paths
export IMAGE_DIR="$BASE_DIR/image"
export IMAGE_FILENAME="debian-bullseye-amd64.img"
export IMAGE_PATH="$IMAGE_DIR/$IMAGE_FILENAME"
export IMAGE_MOUNT_DIR="$IMAGE_DIR/mnt"
export SSH_KEY_PATH="$IMAGE_DIR/id_rsa"

# gcov tool — must match the GCC version used to build the kernel (GCC 10 on Debian 11 bullseye)
export GCOV="gcov-10"

# QEMU VM log file
export DEBUG_VM_LOG_FILE="$BASE_DIR/vm_boot.linux-${KERNEL_GIT_TAG}.log"

if [[ "${KERNEL_TESTS_DEBUG_ENV:-0}" == "1" ]]; then
    echo "env: kernel=${KERNEL_GIT_TAG} localversion=${KERNEL_LOCALVERSION}"
fi
