# ==============================================================================
# Zephyr + ESP-IDF Development Environment (modular)
# ==============================================================================
# Base image with generic dev tooling + a python venv/west, plus each stack
# (Zephyr, ESP-IDF, ...) installed by its own toggleable script in scripts/.
# Source code stays on your host and is mounted in at /workspace.
#
# Two ways in, both work:
#   docker compose exec devbox bash        (no setup needed)
#   ssh root@localhost -p 2222             (password set below)
#
# To add a new stack later:
#   1. Write scripts/install-<name>.sh (self-contained, installs under /opt).
#   2. Add ARG INSTALL_<NAME>=false + a matching RUN block below.
#   3. Add the build arg to docker-compose.yml.
# ==============================================================================

ARG DEBIAN_VERSION=stable-slim
ARG VIRTUAL_ENV=/opt/venv
ARG SSH_PASSWORD="zephyr"

ARG INSTALL_ZEPHYR=true
ARG INSTALL_ESPIDF=true

# Zephyr settings
ARG ZEPHYR_VERSION=v3.6.0
ARG ZEPHYR_SDK_VERSION=0.16.8
ARG TOOLCHAIN_LIST="-t xtensa-espressif_esp32_zephyr-elf \
                    -t xtensa-espressif_esp32s2_zephyr-elf \
                    -t xtensa-espressif_esp32s3_zephyr-elf"

# ESP-IDF settings — pinned to an exact commit, not just the tag, so a
# force-moved tag can never silently change what gets built.
# https://github.com/espressif/esp-idf/releases/tag/v5.5.1
ARG ESPIDF_VERSION_TAG=v5.5.1
ARG ESPIDF_COMMIT=fcae32885b0296b32044cb99ecbdc50d98dddb83
ARG ESPIDF_TARGETS=esp32,esp32s2,esp32s3,esp32c3


FROM debian:${DEBIAN_VERSION}

# ARGs are forgotten after FROM, so re-declare the ones still needed below.
ARG VIRTUAL_ENV
ARG SSH_PASSWORD
ARG INSTALL_ZEPHYR
ARG INSTALL_ESPIDF
ARG ZEPHYR_VERSION
ARG ZEPHYR_SDK_VERSION
ARG TOOLCHAIN_LIST
ARG ESPIDF_VERSION_TAG
ARG ESPIDF_COMMIT
ARG ESPIDF_TARGETS

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------------------------
# Base layer: generic dev tooling every stack needs, regardless of which
# stack(s) are enabled. Keep this stack-agnostic.
# ------------------------------------------------------------------------------
RUN apt-get update && apt-get install --no-install-recommends -y \
        git cmake ninja-build gperf build-essential device-tree-compiler \
        wget curl ca-certificates \
        python3 python3-pip python3-venv \
        xz-utils file locales vim nano \
        openssh-server \
    && rm -rf /var/lib/apt/lists/*

# Shared Python venv + west. A venv keeps our Python tools separate from the
# system Python. Putting it on PATH means `west`/`idf.py` just work
# everywhere, even in non-interactive commands like `docker compose run`.
ENV VIRTUAL_ENV=${VIRTUAL_ENV}
RUN python3 -m venv ${VIRTUAL_ENV}
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"
RUN pip install --no-cache-dir west

RUN sed -i '/en_US.UTF-8/s/^#//' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Env vars so builds work without extra setup. Harmless to set even if a
# stack is disabled — the paths just won't exist, and nothing references them.
#
# IDF_TOOLS_PATH in particular MUST be set before install-espidf.sh runs
# below: ESP-IDF's own install.sh reads it to decide where to put its
# toolchains/python-env, and silently falls back to ~/.espressif if it's
# unset - which then doesn't match where docker-compose.yml mounts the
# espidf-tools volume, and idf.py can't find its venv at runtime.
ENV ZEPHYR_BASE=/opt/toolchains/zephyr
ENV ZEPHYR_SDK_INSTALL_DIR=/opt/toolchains/zephyr-sdk-${ZEPHYR_SDK_VERSION}
ENV IDF_TOOLS_PATH=/opt/toolchains/esp-idf-tools

# ------------------------------------------------------------------------------
# Optional stacks. Each script is self-contained; see scripts/ comments.
# ------------------------------------------------------------------------------
COPY scripts/ /opt/build-scripts/
RUN chmod +x /opt/build-scripts/*.sh

RUN if [ "$INSTALL_ZEPHYR" = "true" ]; then \
      /opt/build-scripts/install-zephyr.sh "${ZEPHYR_VERSION}" "${ZEPHYR_SDK_VERSION}" "${TOOLCHAIN_LIST}"; \
    fi

RUN if [ "$INSTALL_ESPIDF" = "true" ]; then \
      /opt/build-scripts/install-espidf.sh "${ESPIDF_VERSION_TAG}" "${ESPIDF_COMMIT}" "${ESPIDF_TARGETS}"; \
    fi

# ------------------------------------------------------------------------------
# Add future stacks here, same pattern:
#
# ARG INSTALL_RUST=false
# RUN if [ "$INSTALL_RUST" = "true" ]; then \
#       /opt/build-scripts/install-rust.sh; \
#     fi
# ------------------------------------------------------------------------------

# Editor tooling: clangd (language server) + clang-format. Kept in its own
# layer after the slow Zephyr/ESP-IDF installs so tweaking it doesn't
# invalidate their cache.
RUN apt-get update && apt-get install --no-install-recommends -y \
        clangd clang-format \
    && rm -rf /var/lib/apt/lists/*

# Auto-activate the west venv + Zephyr env on interactive shell start. Each
# source is guarded so a disabled stack doesn't break your shell.
#
# ESP-IDF's export.sh is deliberately NOT auto-sourced here, unlike the
# others - Espressif's own docs recommend an opt-in alias instead of sourcing
# it in .bashrc, and this project needs that: export.sh sets IDF_PATH to this
# real, standalone ESP-IDF checkout, and Zephyr's ESP32 support (hal_espressif)
# has its own bundled, version-pinned copy of ESP-IDF's cmake files. If
# IDF_PATH is already set when you `west build` a Zephyr ESP32 app, cmake
# pulls in bits of both and breaks (e.g. "include could not find requested
# file: uf2", "Unknown CMake command depgraph_add_edge") since the two don't
# share a cmake API version. Run `get_idf` in a shell before working on an
# ESP-IDF (non-Zephyr) project; leave it unset otherwise.
RUN { \
      echo "source ${VIRTUAL_ENV}/bin/activate"; \
      echo "[ -f \${ZEPHYR_BASE}/zephyr-env.sh ] && source \${ZEPHYR_BASE}/zephyr-env.sh"; \
      echo "[ -f /opt/toolchains/esp-idf/export.sh ] && alias get_idf='. /opt/toolchains/esp-idf/export.sh'"; \
    } >> /root/.bashrc

# ------------------------------------------------------------------------------
# SSH server (so you can connect with a terminal or VS Code Remote-SSH)
# ------------------------------------------------------------------------------
RUN echo "root:${SSH_PASSWORD}" | chpasswd
RUN sed -i 's/#\?PermitRootLogin.*/PermitRootLogin yes/'        /etc/ssh/sshd_config && \
    sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
RUN mkdir -p /var/run/sshd
EXPOSE 22

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# ------------------------------------------------------------------------------
# Where your project lives (mounted from your host)
# ------------------------------------------------------------------------------
# /workspace is a symlink INTO the west workspace topdir, not a plain mounted
# directory. `west build`/`flash`/etc. only get loaded when west can find a
# .west/config by walking UP from the current directory — that lives in
# /opt/toolchains, so any project needs to be reachable from inside that
# tree. Mount your project(s) at /opt/toolchains/workspace in
# docker-compose.yml; this symlink makes them also visible at /workspace.
RUN mkdir -p /opt/toolchains/workspace && \
    ln -s /opt/toolchains/workspace /workspace

WORKDIR /workspace
CMD ["/bin/bash"]
