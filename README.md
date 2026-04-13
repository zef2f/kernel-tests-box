# kernel-tests-box

A Docker-based environment for functional testing of Linux kernels with coverage collection.

---

## Directory Structure

```
kernel-tests-box/
├── run-hwmon-driver.sh         # One-command workflow for a single hwmon driver
├── build-docker-image.sh       # Build the Docker image
├── run-container.sh            # Start the container
├── enter-container.sh          # Get a shell inside the container
├── run-all.sh                  # Main control script (build → container → setup)
├── project.env                 # Container name, SSH port defaults
├── Dockerfile                  # Debian 11 (bullseye) build environment
├── config/
│   └── kernel/                 # Base kernel configs
├── patches/
│   ├── kernel/                 # Patches applied to the kernel before build
│   └── qemu/                   # Patches applied to QEMU before build
├── scripts/
│   ├── 01-setup-env.sh         # Environment variables (kernel tag, gcov, paths)
│   ├── 02-build-kernel.sh      # Clone, configure, and build the kernel
│   ├── 03-build-qemu.sh        # Clone and build QEMU from source
│   ├── 05-build-image.sh       # Build Debian 11 guest root filesystem (debootstrap)
│   ├── ensure-hwmon-tests.sh   # Clone hwmon-i2c-stub-tests when missing
│   ├── run-vm.sh               # Start the QEMU VM for testing
│   ├── collect-gcov-in-vm.sh   # Run inside VM to collect gcov coverage data
│   ├── render-gcov-report.sh   # Generate LCOV HTML report from collected data
│   ├── ssh-to-vm.sh            # SSH into the running VM
│   ├── scp-to-vm.sh            # Copy files to the VM
│   ├── scp-from-vm.sh          # Copy files from the VM
│   └── tools/
│       └── diff_configs.sh     # Compare two kernel .config files
└── volume/                     # Persistent storage mounted into the container
```

---

## 1. Configuration

Before starting, review two files:

1. **`project.env`** — container name, SSH port for VM access.
2. **`scripts/01-setup-env.sh`** — kernel repository, branch (`KERNEL_GIT_TAG`),
   local version suffix (`KERNEL_LOCALVERSION`).

**To select the kernel version**, set `KERNEL_GIT_TAG` in `01-setup-env.sh`:

```bash
export KERNEL_GIT_TAG="<kernel-tag>"
# Available tag examples are listed in scripts/01-setup-env.sh
```

**To enable gcov coverage collection**, keep `gcov` in `KERNEL_LOCALVERSION`:

```bash
export KERNEL_LOCALVERSION="<build-suffix>-gcov"   # gcov enabled
# export KERNEL_LOCALVERSION="<build-suffix>"      # gcov disabled
```

---

## 2. Main Workflow

### One-Command hwmon Driver Run

From a fresh clone:

```bash
./run-hwmon-driver.sh lm90
```

This command:
- builds or reuses the Docker image and container;
- clones `hwmon-i2c-stub-tests` from `https://github.com/zef2f/hwmon-i2c-stub-tests.git`;
- builds or reuses the kernel, QEMU, and guest image;
- starts or reuses the VM;
- runs the requested driver test and stores artifacts in `volume/artifacts/`.

### Automated Full Setup

```bash
./run-all.sh        # build image → start container → build kernel + QEMU + rootfs
```

### Stage-by-Stage

```bash
./run-all.sh build      # Build the Docker image
./run-all.sh container  # Start the container
./run-all.sh kernel     # Build the kernel (inside container)
./run-all.sh qemu       # Build QEMU from source (inside container)
./run-all.sh image      # Build the Debian 11 guest rootfs (inside container)
./run-all.sh setup      # Run kernel + qemu + image in sequence
```

---

## 3. Running Tests

```bash
# Start the VM (serial console, SSH on localhost:22000)
./scripts/run-vm.sh

# From another terminal: SSH into the VM
./scripts/ssh-to-vm.sh

# Copy a test script to the VM
./scripts/scp-to-vm.sh ./my-test.sh /root/

# Copy results back from the VM
./scripts/scp-from-vm.sh /root/results.tar ./
```

---

## 4. Coverage Collection

After running tests inside the VM:

```bash
# 1. Inside the VM — collect gcov data
./collect-gcov-in-vm.sh         # produces /root/gcov_data.tar

# 2. On the host — transfer the archive
./scripts/scp-from-vm.sh /root/gcov_data.tar ./

# 3. On the host / inside the container — generate HTML report
./scripts/render-gcov-report.sh gcov_data.tar "My Test Suite"
```

The `*.gcno` archive (`gcov_build-*.tar.gz`) is produced automatically by
`02-build-kernel.sh` after a gcov build and must reside at the same absolute
path as during compilation when generating the report.

---

## License

GPL-3.0-or-later. See the `LICENSE` file for details.
