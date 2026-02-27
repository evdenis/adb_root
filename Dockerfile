# Dockerfile — Build AOSP adbd (aarch64) using the Soong build system
#
# Usage:
#   DOCKER_BUILDKIT=1 docker build --target=binary --output=system/bin/ .

# ── Stage 1: Builder ──
FROM ubuntu:20.04 AS builder

ARG AOSP_TAG=android-security-10.0.0_r75

ENV DEBIAN_FRONTEND=noninteractive

# Install AOSP build dependencies and repo tool
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl python3 python-is-python3 \
    build-essential zip unzip file bc \
    ca-certificates openssh-client \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo \
        -o /usr/local/bin/repo \
    && chmod +x /usr/local/bin/repo \
    && git config --global user.email "build@localhost" \
    && git config --global user.name "Build" \
    && git config --global color.ui false

WORKDIR /aosp

# Sync minimal AOSP tree and trim to save space
COPY docker/ /docker/
RUN bash /docker/sync-aosp.sh "$AOSP_TAG" /docker/aosp-projects.list

# Apply adbd root patches and build.
# build-adbd.sh uses the "eng" lunch target (e.g. aosp_arm64-eng) because
# it sets ALLOW_ADBD_ROOT=1, which enables the root code paths in adbd.
# userdebug/user builds do not define this flag and would produce a binary
# that refuses to run as root.
COPY patches/ /patches/
COPY build-adbd.sh /build-adbd.sh
RUN python3 /patches/apply.py /aosp/system/core \
    && bash /build-adbd.sh

# ── Stage 2: Extract binary ──
FROM scratch AS binary
COPY --from=builder /aosp/out/target/product/generic_arm64/system/bin/adbd /adbd
