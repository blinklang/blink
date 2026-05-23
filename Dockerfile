FROM debian:bookworm-slim

ARG BLINK_VERSION=v0.44.0
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

RUN curl -fsSL "https://github.com/blinklang/blink/releases/download/${BLINK_VERSION}/blink-linux-x86_64.tar.gz" \
        -o /tmp/blink.tar.gz \
    && tar -xzf /tmp/blink.tar.gz -C /tmp \
    && mkdir -p /usr/local/share/blink \
    && cp /tmp/blink-linux-x86_64/bin/blink /usr/local/bin/blink \
    && chmod +x /usr/local/bin/blink \
    && cp /tmp/blink-linux-x86_64/share/blink/libblink_std.a \
          /tmp/blink-linux-x86_64/share/blink/libblink_std.h \
          /tmp/blink-linux-x86_64/share/blink/runtime.h \
          /usr/local/share/blink/ \
    && rm -rf /tmp/blink.tar.gz /tmp/blink-linux-x86_64

WORKDIR /workspace

ENTRYPOINT ["blink"]
CMD ["--help"]
