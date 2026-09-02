#!/usr/bin/env bash
# Installs a shared Zephyr checkout + west workspace + SDK, baked into the
# image at /opt/toolchains.
set -euo pipefail
ZEPHYR_VERSION="${1:?usage: install-zephyr.sh <zephyr-version> <sdk-version> <toolchain-list>}"
ZEPHYR_SDK_VERSION="${2:?}"
TOOLCHAIN_LIST="${3:?}"

mkdir -p /opt/toolchains
cd /opt/toolchains

# Clone Zephyr and check out a known-good version. Tip: if a specific board
# ever breaks on a release tag, swap ${ZEPHYR_VERSION} for an exact commit
# hash the same way install-espidf.sh pins ESP-IDF.
git clone --branch "${ZEPHYR_VERSION}" --depth 1 \
    https://github.com/zephyrproject-rtos/zephyr.git
pip install --no-cache-dir -r zephyr/scripts/requirements-base.txt

# Initialise the West workspace and pull in Zephyr's modules.
# --narrow and --depth 1 make this much faster and smaller.
west init -l zephyr
west update --narrow -o=--depth=1

# Fetch the Espressif binary blobs (needed for ESP32 WiFi/Bluetooth).
west blobs fetch hal_espressif

# Zephyr SDK: the actual compilers. ${HOSTTYPE} resolves to x86_64 or
# aarch64 automatically. SDK releases ship as plain .tar.xz archives.
wget -q --show-progress \
    "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_SDK_VERSION}/zephyr-sdk-${ZEPHYR_SDK_VERSION}_linux-${HOSTTYPE}_minimal.tar.xz"
tar xf "zephyr-sdk-${ZEPHYR_SDK_VERSION}_linux-${HOSTTYPE}_minimal.tar.xz"
rm "zephyr-sdk-${ZEPHYR_SDK_VERSION}_linux-${HOSTTYPE}_minimal.tar.xz"

# Install only the toolchains listed at the top of the Dockerfile.
# Registers the CMake package (-c) for the given toolchains (-t).
cd "/opt/toolchains/zephyr-sdk-${ZEPHYR_SDK_VERSION}"
bash setup.sh -c ${TOOLCHAIN_LIST}
