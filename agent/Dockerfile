# Dockerfile for ICP-CC (ICP Autorun/Script Marketplace) + Containerized development environment

FROM rust:1.91

# Environment variables
ENV HOME=/home/ubuntu \
    XDG_DATA_HOME=/home/ubuntu/.cache/data \
    PATH=/usr/lib/postgresql/17/bin:/home/ubuntu/.cache/data/dfx/bin:/home/ubuntu/.cache/data/bin:/home/ubuntu/.cache/bin:/home/ubuntu/.cargo/bin:/usr/local/cargo/bin:/home/ubuntu/.local/bin:/home/ubuntu/.opencode/bin:/home/ubuntu/bin:/home/ubuntu/.npm-global/bin:/home/ubuntu/.venv/bin:$PATH \
    POCKET_IC_BIN=/home/ubuntu/bin/pocket-ic \
    RUST_BACKTRACE=1 \
    VIRTUAL_ENV=/home/ubuntu/.venv

# Create working directory and non-root user
RUN useradd -m -u 1000 ubuntu && mkdir -p $HOME/.git/hooks $HOME/bin $XDG_DATA_HOME
WORKDIR $HOME

# Add tini for proper signal handling
ENV TINI_VERSION=v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

# Install dfx (DFINITY Canister SDK). Used for local replica in e2e tests
# (dapps.run_poll, dapps.create_profile_to_vote). The binary lives under
# $HOME/.cache/data/dfx/bin (on PATH via the ENV above) — fresh home-cache
# volumes copy this baked-in path on first init (see target-cache pattern
# below). dfx emits a deprecation pointer to icp-cli on every call; we keep
# dfx because icp-cli does not yet match dfx feature parity for `dfx start`
# + `dfx deploy`. When icp-cli reaches parity, swap this block.
RUN DFXVM_INIT_YES=yes sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)" \
    && dfxvm default 0.32.0

# Install deps
RUN apt update && \
    apt install -y libunwind-dev curl libssl-dev pkg-config gzip build-essential ca-certificates less jq clang mold sqlite3 curl gosu postgresql tmux \
    # Docker CLI for running docker commands inside the container
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources-docker.list \
    && cat /etc/apt/sources-docker.list >> /etc/apt/sources.list.d/docker.list \
    && apt update && apt install -y docker-ce-cli docker-compose-plugin

# Install Node.js directly from NodeSource repository
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs

# Install pip
RUN apt install -y python3-pip python3-venv

# Install Flutter dependencies
RUN apt-get update && apt-get install -y \
    xz-utils \
    zip \
    unzip \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN chown -R ubuntu:ubuntu $HOME /usr/local/cargo /usr/local/rustup

# Install Playwright system dependencies (requires root)
RUN npx playwright install-deps chromium && chown -R ubuntu:ubuntu /home/ubuntu

# Switch to non-root user
USER ubuntu

# Install pocket-ic-server
RUN curl -L https://github.com/dfinity/pocketic/releases/download/10.0.0/pocket-ic-x86_64-linux.gz -o $HOME/bin/pocket-ic.gz \
    && gunzip $HOME/bin/pocket-ic.gz && chmod +x $HOME/bin/pocket-ic

# Install Rust
RUN rustup target add x86_64-unknown-linux-gnu wasm32-unknown-unknown \
    && rustup toolchain install nightly-2025-11-27 --profile=complete \
    && curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash

# Install cargo tools using binstall for faster installation
RUN cargo binstall --no-confirm cargo-make cargo-nextest sqlx-cli ripgrep cargo-sweep wasm-pack

# Install UV to .local/bin (not .cargo/bin which gets shadowed by cargo-cache volume)
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$HOME/.local/bin" sh

# Create Python virtual environment and install common packages
RUN $HOME/.local/bin/uv venv $HOME/.venv \
    && $HOME/.local/bin/uv pip install python-dotenv pytest black ruff

# Install Just build system
RUN curl -Lo /tmp/just.tar.gz "https://github.com/casey/just/releases/download/1.35.0/just-1.35.0-x86_64-unknown-linux-musl.tar.gz" \
    && tar -xzf /tmp/just.tar.gz -C /tmp \
    && mv /tmp/just $HOME/.local/bin/ \
    && chmod +x $HOME/.local/bin/just \
    && rm /tmp/just.tar.gz

# Configure npm to use user-specific global directory and install tools
RUN mkdir -p ~/.npm-global \
    && npm config set prefix '~/.npm-global' \
    && echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc \
    && echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.profile \
    && export PATH=~/.npm-global/bin:$PATH \
    && npm install -g @anthropic-ai/claude-code happy-coder playwright @lightpanda/browser \
    && npx playwright install chromium

# Install OpenCode
RUN curl -fsSL https://opencode.ai/install | bash

# Install Plasmate
RUN curl -fsSL https://plasmate.app/install.sh | sh

# Install Omnigent (the `omni`/`omnigent` CLI). `uv tool install` resolves the
# full dependency tree (incl. pre-release opentelemetry-instrumentation-* that
# plain pip rejects) into an isolated env. Pinned to match the verified
# host-registration flow. See agent/entrypoint.sh for auto host registration.
#
# CRITICAL — placement: docker-compose mounts a named `home-cache` volume over
# /home/ubuntu/.cache, and XDG_DATA_HOME points there, so uv would otherwise put
# the tool env, bin shims, AND the managed CPython interpreter (the venv's
# `python` is a symlink into uv's python-install dir) all under .cache → MASKED
# & invisible at runtime. The shims vanish, `omnigent`/`omni` aren't found, and
# even if a shim is reached its shebang interpreter is a dangling symlink (the
# classic "cannot execute: required file not found" / setsid ENOENT) → host
# never registers. We force all three (tools, shims, managed python) into
# /home/ubuntu/.local (never volume-masked, always on PATH) so every container
# sees them straight from the image layer, regardless of any stale cache volume.
ENV UV_TOOL_DIR=/home/ubuntu/.local/share/uv/tools \
    UV_TOOL_BIN_DIR=/home/ubuntu/.local/bin \
    UV_PYTHON_INSTALL_DIR=/home/ubuntu/.local/share/uv/python
RUN uv tool install --python 3.12 omnigent==0.5.1

# Install Flutter SDK for ICP-CC project
RUN git clone https://github.com/flutter/flutter.git /home/ubuntu/flutter \
    && /home/ubuntu/flutter/bin/flutter config --enable-web

# Pin Flutter to the stable release the app is verified against.
# Upgraded from 3.38.3 → 3.44.6 (commit ed220a70): cleared the RenderAbsorbPointer
# Overlay binding quirk that blocked 6 e2e flows. Dart 3.10.1→3.12.2, DevTools
# 2.51.1→2.57.0. Checked out as a separate layer so the expensive clone above stays cached.
RUN cd /home/ubuntu/flutter && git checkout 3.44.6

# Add Flutter to PATH
ENV PATH="/home/ubuntu/flutter/bin:${PATH}"

# Configure git hooks
COPY --chown=ubuntu:ubuntu agent/git-hooks/ $HOME/.git-hooks/
RUN chmod +x $HOME/.git-hooks/commit-msg \
    && git config --global core.hooksPath $HOME/.git-hooks \
    && git config --global init.defaultBranch main

# Copy entrypoint script (runs as root, fixes perms, drops to ubuntu)
USER root

# Flutter Linux desktop build deps (flutter build linux drives CMake + Ninja + GTK).
# Installed here (late) so the heavy Rust/Flutter/Playwright layers above stay cached.
RUN apt-get update && apt-get install -y \
        cmake ninja-build libgtk-3-dev liblzma-dev libstdc++-12-dev libsecret-1-dev \
    && rm -rf /var/lib/apt/lists/*
# Pre-create target/ (1000-owned) so the target-cache named volume initializes
# with correct ownership when running as the host user (UID 1000).
# Docker's volume-init copies this image-baked path (bind mounts are masked),
# so a fresh volume inherits ubuntu ownership.
RUN mkdir -p /code/icp-cc/target && chown ubuntu:ubuntu /code/icp-cc/target
# Same treatment for the pub cache and Flutter engine cache volumes (see
# docker-compose.yml). Fresh named volumes are otherwise root-owned and the
# non-root container can't write to them.
RUN mkdir -p /home/ubuntu/.pub-cache \
        /home/ubuntu/flutter/bin/cache \
        /home/ubuntu/.omnigent \
        /home/ubuntu/.cache/data/dfx \
        /home/ubuntu/.cache/dfinity \
    && chown -R ubuntu:ubuntu /home/ubuntu/.pub-cache /home/ubuntu/flutter/bin/cache /home/ubuntu/.omnigent /home/ubuntu/.cache/data/dfx /home/ubuntu/.cache/dfinity
COPY agent/entrypoint.sh $HOME/entrypoint.sh
RUN chmod +x $HOME/entrypoint.sh

# Default entrypoint uses tini for signal handling (compose overrides with entrypoint.sh)
ENTRYPOINT ["/tini", "--"]
