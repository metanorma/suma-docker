FROM metanorma/metanorma:1.16.9
LABEL maintainer="Metanorma Team <metanorma@ribose.com>"

ARG EENGINE_VERSION=5.2.7

RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        EENGINE_ARCH="x86-64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        EENGINE_ARCH="arm64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    EENGINE_FILE="eengine-${EENGINE_VERSION}-lnx-${EENGINE_ARCH}-sbcl" && \
    curl -L -O "https://github.com/expresslang/eengine-releases/releases/download/eeng-${EENGINE_VERSION}/${EENGINE_FILE}" && \
    chmod +x "${EENGINE_FILE}" && \
    mv "${EENGINE_FILE}" /usr/local/bin/eengine

# Multi-architecture setup for eep (x86-64 binary)
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ]; then \
        # Install QEMU user-mode emulation for x86-64 binaries \
        apt-get update && \
        apt-get install -y qemu-user-static binfmt-support && \
        \
        # Add amd64 architecture support \
        dpkg --add-architecture amd64 && \
        apt-get update && \
        apt-get install -y libc6:amd64 binutils:amd64; \
    else \
        # For x86-64, just add multi-arch support \
        dpkg --add-architecture amd64 && \
        apt-get update && \
        apt-get install -y binutils:amd64; \
    fi

# Install eep binary (x86-64 only, works on ARM64 via QEMU)
RUN curl -L -o /usr/local/bin/eep \
        "https://github.com/expresslang/eep-releases/raw/main/linux/eep-linux-x64" && \
    chmod +x /usr/local/bin/eep

WORKDIR /metanorma
