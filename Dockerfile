FROM debian:bookworm-slim

ARG BLINK_VERSION=v0.23.3
ARG ZIG_VERSION=0.13.0

RUN apt-get update && apt-get install -y \
    gcc \
    libc6-dev \
    libgc-dev \
    libsqlite3-dev \
    git \
    curl \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" \
    -o /tmp/zig.tar.xz \
    && tar -xf /tmp/zig.tar.xz -C /usr/local \
    && ln -s /usr/local/zig-linux-x86_64-${ZIG_VERSION}/zig /usr/local/bin/zig \
    && rm /tmp/zig.tar.xz

RUN curl -fsSL "https://github.com/nhumrich/blink/releases/download/${BLINK_VERSION}/blink-linux-x86_64" \
    -o /usr/local/bin/blink \
    && chmod +x /usr/local/bin/blink

WORKDIR /workspace

ENTRYPOINT ["blink"]
CMD ["--help"]
