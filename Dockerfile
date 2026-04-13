# Dockerfile for kernel-tests-box
FROM debian:bullseye

ARG USERNAME=user
ARG UID=1000
ARG GID=1000

ENV USER=${USERNAME}
ENV HOME=/home/${USERNAME}
ENV DEBIAN_FRONTEND=noninteractive

# Kernel build dependencies
# Packages required for building kernel images on Debian 11 bullseye.
RUN apt-get update && \
    apt-get dist-upgrade -y && \
    apt-get install -y \
        build-essential \
        flex \
        bison \
        bc \
        libssl-dev \
        libelf-dev \
        git \
        kmod \
        python3-minimal \
        python3-setuptools \
        wget \
        curl \
        ccache \
        ca-certificates \
        cpio \
        libgmp-dev \
        libmpc-dev \
        pigz \
        pbzip2 \
        linux-base \
        libudev1 \
        udev \
        klibc-utils \
        initramfs-tools-core \
        initramfs-tools \
    && apt-get clean

COPY config/docker/qemu-build-packages.txt /tmp/qemu-build-packages.txt

# QEMU build dependencies
RUN apt-get update && \
    grep -Ev '^\s*(#|$)' /tmp/qemu-build-packages.txt | xargs apt-get install -y && \
    apt-get clean && \
    rm -f /tmp/qemu-build-packages.txt

# Optional user tools + lcov for coverage reports + debootstrap for VM image creation
RUN apt-get update && \
    apt-get install -y \
        sudo \
        bash-completion \
        procps \
        vim-common \
        nano \
        lcov \
        rename \
        fdisk \
        patch \
        openssl \
        golang \
        debootstrap \
        e2fsprogs \
        qemu-utils \
    && apt-get clean

# Python packages required by QEMU build system (meson)
RUN pip3 install tomli

# Create a non-root user
RUN groupadd -g ${GID} ${USERNAME} && \
    useradd -u ${UID} -g ${GID} -ms /bin/bash ${USERNAME} && \
    usermod -aG sudo,disk ${USERNAME} && \
    echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chown ${USERNAME}:${USERNAME} /home/${USERNAME}

USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Copy all project files into the container
COPY --chown=${USERNAME}:${USERNAME} . /home/user/kernel-tests-box
WORKDIR /home/user/kernel-tests-box

CMD ["/bin/bash"]
