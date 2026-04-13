#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Copyright (C) 2025 Vasiliy Kovalev <kovalev@altlinux.org>

set -eo pipefail
source "$(dirname "$0")/01-setup-env.sh"

# --- CONFIGURATION ---
# Image size in megabytes
IMAGE_SIZE_MB=4096

# Debian mirror to use inside the container
DEBIAN_MIRROR="http://deb.debian.org/debian"

# Base packages to include via debootstrap --include
# Test-suite-specific packages should be installed separately in the VM
DEBOOTSTRAP_INCLUDE="openssh-server,curl,wget,kmod,iproute2,iputils-ping,\
sudo,bash-completion,vim-tiny,python3"

# Additional packages installed via chroot after debootstrap
PACKAGES_TO_INSTALL="lcov i2c-tools"
# --------------------

help() {
    echo "Usage: $0"
    echo "Builds a Debian 11 (bullseye) root filesystem image using debootstrap."
    echo "Requires root (sudo) for mount/debootstrap operations."
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    help
    exit 0
fi

cleanup() {
    echo "--> Running cleanup (unmounting virtual filesystems)..."
    for fs in proc sys dev; do
        if mountpoint -q "$IMAGE_MOUNT_DIR/$fs"; then
            sudo umount "$IMAGE_MOUNT_DIR/$fs"
        fi
    done
    if mountpoint -q "$IMAGE_MOUNT_DIR"; then
        sudo umount "$IMAGE_MOUNT_DIR"
    fi
}
trap cleanup EXIT

echo "▶ Starting guest image preparation (debootstrap Debian 11 bullseye)..."

mkdir -p "$IMAGE_DIR" "$IMAGE_MOUNT_DIR"

# 1. Create raw disk image (whole disk = ext4 filesystem, no partition table)
#    root=/dev/sda works with QEMU -kernel when the disk is a raw filesystem
if [ ! -f "$IMAGE_PATH" ]; then
    echo "Creating ${IMAGE_SIZE_MB}MB raw image..."
    dd if=/dev/zero of="$IMAGE_PATH" bs=1M count="$IMAGE_SIZE_MB"
    mkfs.ext4 -F "$IMAGE_PATH"
else
    echo "Image $IMAGE_PATH already exists. Skipping creation."
fi

# 2. Mount image
echo "Mounting image..."
sudo mount -o loop "$IMAGE_PATH" "$IMAGE_MOUNT_DIR"

# 3. Run debootstrap
echo "Running debootstrap (this may take a while)..."
sudo debootstrap \
    --arch=amd64 \
    --include="$DEBOOTSTRAP_INCLUDE" \
    bullseye \
    "$IMAGE_MOUNT_DIR" \
    "$DEBIAN_MIRROR"

# 4. Configure the system inside the image
echo "Configuring the system..."

# Hostname
echo "kernel-tests-vm" | sudo tee "$IMAGE_MOUNT_DIR/etc/hostname"

# fstab: whole disk is root, no partition table
echo "/dev/sda / ext4 errors=remount-ro 0 1" | sudo tee "$IMAGE_MOUNT_DIR/etc/fstab"

# Network: eth0 via DHCP (net.ifnames=0 in kernel cmdline keeps the name eth0)
sudo tee "$IMAGE_MOUNT_DIR/etc/network/interfaces" > /dev/null << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# DNS fallback
echo "nameserver 8.8.8.8" | sudo tee "$IMAGE_MOUNT_DIR/etc/resolv.conf"

# Allow root login via serial console and SSH (needed for test execution)
sudo tee "$IMAGE_MOUNT_DIR/etc/ssh/sshd_config.d/99-kernel-tests.conf" > /dev/null << 'EOF'
PermitRootLogin yes
PermitEmptyPasswords yes
EOF

# 5. Prepare chroot environment
sudo mount --bind /dev  "$IMAGE_MOUNT_DIR/dev"
sudo mount --bind /sys  "$IMAGE_MOUNT_DIR/sys"
sudo mount -t proc /proc "$IMAGE_MOUNT_DIR/proc"
sudo cp /etc/resolv.conf "$IMAGE_MOUNT_DIR/etc/resolv.conf"

# Enable serial console and SSH autostart
sudo chroot "$IMAGE_MOUNT_DIR" /bin/bash -c "
    systemctl enable serial-getty@ttyS0.service
    systemctl enable ssh
    passwd -d root
"

# Install additional packages
if [ -n "$PACKAGES_TO_INSTALL" ]; then
    sudo chroot "$IMAGE_MOUNT_DIR" /bin/bash -c \
        "apt-get update && apt-get install -y $PACKAGES_TO_INSTALL && apt-get clean"
fi

# 6. Setup SSH key for passwordless access
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -f "$SSH_KEY_PATH" -N ""
fi
sudo mkdir -p "$IMAGE_MOUNT_DIR/root/.ssh"
sudo cp "$SSH_KEY_PATH.pub" "$IMAGE_MOUNT_DIR/root/.ssh/authorized_keys"
sudo chmod 700 "$IMAGE_MOUNT_DIR/root/.ssh"
sudo chmod 600 "$IMAGE_MOUNT_DIR/root/.ssh/authorized_keys"

# 7. Install kernel modules (kernel itself is passed via -kernel QEMU flag)
if [ -d "$KERNEL_BUILD_DIR" ]; then
    echo "Installing kernel modules into the image..."
    cd "$KERNEL_BUILD_DIR"
    sudo make INSTALL_MOD_PATH="$IMAGE_MOUNT_DIR" -j"$(nproc)" modules_install
else
    echo "Warning: KERNEL_BUILD_DIR ($KERNEL_BUILD_DIR) not found. Run 02-build-kernel.sh first."
fi

# END. cleanup via trap
echo "✅ Guest image is ready at: $IMAGE_PATH"
