# DevContainer for Aegis-SPARK: Ubuntu 24.04 (Noble Numbat)
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG ALR_VERSION=2.1.1

# Install system dependencies, cross-compilers, QEMU ARM64, and build utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    gdb-multiarch \
    git \
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    ninja-build \
    pkg-config \
    qemu-system-arm \
    unzip \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Install Alire (alr) binary
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        ALR_ARCH="x86_64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        ALR_ARCH="aarch64"; \
    else \
        ALR_ARCH="x86_64"; \
    fi && \
    curl -fsSL "https://github.com/alire-project/alire/releases/download/v${ALR_VERSION}/alr-${ALR_VERSION}-bin-${ALR_ARCH}-linux.zip" -o /tmp/alr.zip && \
    unzip -q /tmp/alr.zip -d /tmp/alr_extracted && \
    mv /tmp/alr_extracted/bin/alr /usr/local/bin/alr && \
    chmod +x /usr/local/bin/alr && \
    rm -rf /tmp/alr.zip /tmp/alr_extracted

# Install Pixi package manager
RUN curl -fsSL "https://pixi.sh/install.sh" | bash && \
    mv /root/.pixi/bin/pixi /usr/local/bin/pixi && \
    chmod +x /usr/local/bin/pixi

USER vscode
ENV PATH="/home/vscode/.local/bin:/usr/local/bin:${PATH}"

WORKDIR /workspace
