#!/usr/bin/env bash
# Installs ESP-IDF pinned to an exact commit (not just a tag) + its toolchains
# for the given target chips.
set -euo pipefail
ESPIDF_VERSION_TAG="${1:?usage: install-espidf.sh <tag> <commit> <targets>}"
ESPIDF_COMMIT="${2:?}"
ESPIDF_TARGETS="${3:?}"

apt-get update
apt-get install -y --no-install-recommends \
    flex bison libffi-dev libssl-dev libusb-1.0-0
rm -rf /var/lib/apt/lists/*

mkdir -p /opt/toolchains
cd /opt/toolchains

# Shallow-clone the release tag (fast, small) then explicitly check out the
# pinned commit hash. For a tag's tip commit these are the same thing today,
# but pinning by hash means a force-moved tag can never change what you build.
git clone --branch "${ESPIDF_VERSION_TAG}" --depth 1 --recursive --shallow-submodules \
    https://github.com/espressif/esp-idf.git
cd esp-idf
git checkout "${ESPIDF_COMMIT}"

# IDF_TOOLS_PATH is set as an image-wide ENV in the Dockerfile.
#
# install.sh refuses to run while a virtualenv is already active - it wants
# to create and manage its own, under IDF_TOOLS_PATH. Our shared west venv
# is on PATH image-wide (see Dockerfile), so hide it for just this step.
VENV_BIN="${VIRTUAL_ENV}/bin"
(
    unset VIRTUAL_ENV
    export PATH="${PATH#"${VENV_BIN}:"}"
    ./install.sh "${ESPIDF_TARGETS}"
)
