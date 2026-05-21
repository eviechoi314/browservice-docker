# syntax=docker/dockerfile:1
ARG BROWSERVICE_VERSION=v0.9.12.2

# ── Build stage ───────────────────────────────────────────────────────────────
FROM ubuntu:22.04 AS builder

ARG BROWSERVICE_VERSION
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        git wget ca-certificates \
        cmake make g++ pkg-config \
        lbzip2 \
        libxcb1-dev libx11-dev \
        libpoco-dev \
        libjpeg-dev \
        zlib1g-dev \
        libpango1.0-dev \
        # CEF link-time dependencies (libcef.so NEEDED entries)
        libatk-bridge2.0-dev \
        libasound2-dev \
        libgbm-dev \
        libxi-dev \
        libcups2-dev \
        libnss3-dev \
        libxcursor-dev \
        libxrandr-dev \
        libxcomposite-dev \
        libxss-dev \
        libxkbcommon-dev \
        libgtk-3-dev \
        libdbus-1-dev \
        libxdamage-dev \
        libxfixes-dev \
        libatspi2.0-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN git clone --depth 1 --branch "${BROWSERVICE_VERSION}" \
        https://github.com/ttalvitie/browservice.git .

# Map Docker TARGETARCH to browservice's CEF arch names, download the
# pre-built patched CEF tarball from the matching release, then compile
# the CEF DLL wrapper via setup_cef.sh before building browservice itself.
RUN set -eux; \
    case "${TARGETARCH:-$(uname -m)}" in \
        amd64|x86_64)  CEF_ARCH=x86_64  ;; \
        arm64|aarch64) CEF_ARCH=aarch64 ;; \
        arm)           CEF_ARCH=armhf   ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    wget -q \
        "https://github.com/ttalvitie/browservice/releases/download/${BROWSERVICE_VERSION}/patched_cef_${CEF_ARCH}.tar.bz2" \
        -O cef.tar.bz2; \
    ./setup_cef.sh cef.tar.bz2; \
    rm cef.tar.bz2

RUN make -j"$(nproc)" release

# chrome-sandbox must be owned root:root with the setuid bit so that
# Chromium can use its process sandbox at runtime.
RUN chown root:root release/bin/chrome-sandbox \
 && chmod 4755 release/bin/chrome-sandbox

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM ubuntu:22.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        # browservice direct dependencies
        libpoco-dev \
        libjpeg-turbo8 \
        zlib1g \
        libpango-1.0-0 libpangoft2-1.0-0 \
        libxcb1 libx11-6 \
        # fonts (alternative to ttf-mscorefonts-installer which requires multiverse + EULA)
        fonts-liberation \
        # virtual framebuffer — browservice needs a display even headless
        xvfb xauth \
        # CEF/Chromium runtime requirements
        libatk-bridge2.0-0 \
        libasound2 \
        libgbm1 \
        libxi6 \
        libcups2 \
        libnss3 \
        libxcursor1 \
        libxrandr2 \
        libxcomposite1 \
        libxss1 \
        libxkbcommon0 \
        libgtk-3-0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/release/bin /opt/browservice/bin

EXPOSE 8080

# The Chromium sandbox inside the container requires the SYS_ADMIN capability.
# Always start this container with: --cap-add=SYS_ADMIN
ENTRYPOINT ["xvfb-run", "--auto-servernum", "--server-args=-screen 0 1280x720x24", \
            "/opt/browservice/bin/browservice"]
