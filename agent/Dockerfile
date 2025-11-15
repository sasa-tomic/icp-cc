# Dockerfile for ICP-CC (ICP Autorun/Script Marketplace) + Containerized development environment
# Based on project requirements with additions for Claude Code and Happy Coder

FROM rust:latest

# Environment variables (from CI Dockerfile)
ENV HOME=/home/ubuntu \
    XDG_DATA_HOME=/home/ubuntu/.cache/data \
    PATH=/home/ubuntu/.cache/data/dfx/bin:/home/ubuntu/.cargo/bin:/home/ubuntu/.local/bin:/home/ubuntu/bin:/home/ubuntu/.npm-global/bin:$PATH \
    POCKET_IC_BIN=/home/ubuntu/bin/pocket-ic \
    RUST_BACKTRACE=1

# Create working directory and non-root user
RUN useradd -m -u 1000 ubuntu && mkdir -p $HOME/.git/hooks $HOME/bin $XDG_DATA_HOME
WORKDIR $HOME

# Add tini for proper signal handling (from CI Dockerfile)
ENV TINI_VERSION=v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

# Install dfx (exact from CI Dockerfile)
RUN DFXVM_INIT_YES=yes sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)" \
    && dfxvm default 0.29.2

# Install deps for ICP-CC project
RUN apt update && \
    apt install -y libunwind-dev curl libssl-dev pkg-config gzip build-essential ca-certificates less jq

# Install Node.js directly from NodeSource repository (required for Flutter and Cloudflare Workers)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs

# Install Flutter dependencies
RUN apt-get update && apt-get install -y \
    xz-utils \
    zip \
    unzip \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install UV for Python package management
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Just build system (as root, it's system-wide)
RUN curl -Lo /tmp/just.tar.gz "https://github.com/casey/just/releases/download/1.35.0/just-1.35.0-x86_64-unknown-linux-musl.tar.gz" \
    && tar -xzf /tmp/just.tar.gz -C /tmp \
    && mv /tmp/just /usr/local/bin/ \
    && chmod +x /usr/local/bin/just \
    && rm /tmp/just.tar.gz

RUN chown -R ubuntu:ubuntu $HOME /usr/local/cargo /usr/local/rustup

# Switch to non-root user
USER ubuntu

# Install Rust (exact from CI Dockerfile)
RUN rustup target add x86_64-unknown-linux-gnu wasm32-unknown-unknown \
    && rustup toolchain install nightly --profile=complete \
    && curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash

# Install cargo tools using binstall for faster installation
RUN cargo binstall cargo-make cargo-nextest wasm-pack ripgrep

# Configure npm to use user-specific global directory and install tools
RUN mkdir -p ~/.npm-global \
    && npm config set prefix '~/.npm-global' \
    && echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc \
    && echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.profile \
    && export PATH=~/.npm-global/bin:$PATH \
    && npm install -g @anthropic-ai/claude-code happy-coder \
    && npm install -g wrangler @openai/codex

# Install Flutter SDK for ICP-CC project
RUN git clone https://github.com/flutter/flutter.git /home/ubuntu/flutter \
    && /home/ubuntu/flutter/bin/flutter config --enable-web \
    && echo 'export PATH=/home/ubuntu/flutter/bin:$PATH' >> ~/.bashrc \
    && echo 'export PATH=/home/ubuntu/flutter/bin:$PATH' >> ~/.profile

# Configure git hooks
COPY --chown=ubuntu:ubuntu agent/git-hooks/ $HOME/.git-hooks/
RUN chmod +x $HOME/.git-hooks/commit-msg \
    && git config --global core.hooksPath $HOME/.git-hooks \
    && git config --global init.defaultBranch main

# Set entrypoint to use tini for proper signal handling
ENTRYPOINT ["/tini", "--"]
