#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Denis Sergeev <denserg.edu@gmail.com>
#
# Verify that all packages declared in the Dockerfile are available in
# the target distro (debian:bullseye by default).
#
# Run on the host before building the Docker image.
# Requires: docker, python3
#
# Usage: $0 [-i IMAGE] [-h]
#   -i IMAGE  Docker image to test against (default: debian:bullseye).
#   -h        Show this help.

set -euo pipefail

DOCKERFILE="$(dirname "$(realpath "$0")")/Dockerfile"
CONFIG_DIR="$(dirname "$DOCKERFILE")/config/docker"
IMAGE="debian:bullseye"

help() {
    echo "Usage: $0 [-i IMAGE] [-h]"
    echo ""
    echo "Checks that all apt/pip packages in Dockerfile are available in IMAGE."
    echo ""
    echo "Options:"
    echo "  -i IMAGE  Docker image to test against (default: $IMAGE)."
    echo "  -h        Show this help."
}

while getopts "hi:" opt; do
    case $opt in
        h) help; exit 0 ;;
        i) IMAGE=$OPTARG ;;
        \?) echo "Invalid option: -$OPTARG" >&2; help; exit 1 ;;
    esac
done

if [[ ! -f "$DOCKERFILE" ]]; then
    echo "Error: Dockerfile not found at $DOCKERFILE" >&2
    exit 1
fi

if ! command -v docker &>/dev/null; then
    echo "Error: docker not found." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Extract apt packages from Dockerfile
# ---------------------------------------------------------------------------

APT_PACKAGES=$(python3 - "$DOCKERFILE" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

pkgs = []
# Match each RUN apt-get install -y ... && apt-get clean block
for block in re.findall(r'apt-get install -y(.*?)apt-get clean', content, re.DOTALL):
    for line in block.splitlines():
        line = line.strip().rstrip('\\').strip()
        # Skip empty lines, comments, shell operators
        if not line or line.startswith('#') or line.startswith('&&') or 'apt-get' in line:
            continue
        pkgs.append(line)

print(' '.join(pkgs))
PYEOF
)

if compgen -G "$CONFIG_DIR/*-packages.txt" >/dev/null; then
    EXTRA_APT_PACKAGES=$(
        grep -hEv '^\s*(#|$)' "$CONFIG_DIR"/*-packages.txt \
            | awk '!seen[$0]++' \
            | xargs
    )
    APT_PACKAGES=$(
        printf '%s\n%s\n' "$APT_PACKAGES" "$EXTRA_APT_PACKAGES" \
            | tr ' ' '\n' \
            | sed '/^$/d' \
            | awk '!seen[$0]++' \
            | xargs
    )
fi

# Extract pip3 packages from Dockerfile
PIP_PACKAGES=$(python3 - "$DOCKERFILE" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

pkgs = []
for m in re.finditer(r'pip3 install\s+(.*)', content):
    pkgs.extend(m.group(1).split())

print(' '.join(pkgs))
PYEOF
)

echo "▶ Testing apt packages against $IMAGE ..."
echo "  (${#APT_PACKAGES} chars of package names)"

# ---------------------------------------------------------------------------
# Test apt packages in a temporary container
# ---------------------------------------------------------------------------

APT_ERRORS=$(docker run --rm "$IMAGE" bash -c "
    apt-get update -q 2>/dev/null
    apt-get install -y --dry-run $APT_PACKAGES 2>&1
" | grep -E "^E: Unable to locate" || true)

if [[ -n "$APT_ERRORS" ]]; then
    echo ""
    echo "❌ Missing apt packages in $IMAGE:"
    echo "$APT_ERRORS" | sed 's/^/  /'
    APT_OK=0
else
    echo "✅ All apt packages available."
    APT_OK=1
fi

# ---------------------------------------------------------------------------
# Test pip packages in a temporary container (with pip installed)
# ---------------------------------------------------------------------------

if [[ -n "$PIP_PACKAGES" ]]; then
    echo "▶ Testing pip packages: $PIP_PACKAGES ..."

    PIP_ERRORS=$(docker run --rm "$IMAGE" bash -c "
        apt-get update -q 2>/dev/null
        apt-get install -y python3-pip 2>/dev/null
        pip3 install --dry-run $PIP_PACKAGES 2>&1
    " | grep -iE "^ERROR|^error|could not find" || true)

    if [[ -n "$PIP_ERRORS" ]]; then
        echo ""
        echo "❌ pip package issues:"
        echo "$PIP_ERRORS" | sed 's/^/  /'
        PIP_OK=0
    else
        echo "✅ All pip packages available."
        PIP_OK=1
    fi
else
    PIP_OK=1
fi

# ---------------------------------------------------------------------------

echo ""
if [[ $APT_OK -eq 1 && $PIP_OK -eq 1 ]]; then
    echo "✅ All dependencies satisfied. Safe to run: ./build-docker-image.sh"
    exit 0
else
    echo "❌ Some dependencies are missing. Fix the Dockerfile before building."
    exit 1
fi
