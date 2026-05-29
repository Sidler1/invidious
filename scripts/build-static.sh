#!/bin/sh
#
# Builds a fully static (musl) Invidious binary plus its runtime assets.
#
# This mirrors the project's Dockerfile build, but is meant to be run inside the
# `crystallang/crystal:*-alpine` image as a plain compiler toolchain (e.g. via
# `docker run` in CI) — it does NOT build or push any container image.
#
# The custom OpenSSL build works around an openssl/crystal memory leak:
#   https://github.com/iv-org/invidious/issues/1438#issuecomment-3087636228
#
# Output: ./invidious (static binary) and a populated ./assets/ directory.
set -eux

OPENSSL_VERSION="${OPENSSL_VERSION:-3.6.2}"
OPENSSL_SHA256="${OPENSSL_SHA256:-aaf51a1fe064384f811daeaeb4ec4dce7340ec8bd893027eee676af31e83a04f}"

apk add --no-cache curl perl linux-headers sqlite-static yaml-static git tar

# Allow git (used to bake CURRENT_VERSION/COMMIT/BRANCH) to read the workspace
# even when it is a bind-mounted directory owned by another user.
git config --global --add safe.directory "$(pwd)"

# --- Build a static OpenSSL ------------------------------------------------
curl -Ls "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" \
  --output "openssl-${OPENSSL_VERSION}.tar.gz"
echo "${OPENSSL_SHA256}  openssl-${OPENSSL_VERSION}.tar.gz" | sha256sum -c
tar -xzf "openssl-${OPENSSL_VERSION}.tar.gz"
( cd "openssl-${OPENSSL_VERSION}" && ./Configure --openssldir=/etc/ssl && make -j"$(nproc)" )

# Drop the distro's dynamic/static OpenSSL so our custom build is picked up.
apk del openssl-dev openssl-libs-static 2>/dev/null || true

# --- Build Invidious -------------------------------------------------------
shards install --production

# Building WITHOUT -Dskip_videojs_download downloads the video.js assets into
# assets/videojs/ at compile time (scripts/fetch-player-dependencies.cr).
PKG_CONFIG_PATH="$(pwd)/openssl-${OPENSSL_VERSION}" \
  crystal build ./src/invidious.cr \
    --release \
    --static --warnings all \
    --link-flags "-lxml2 -llzma"

# Tidy up so the OpenSSL build tree isn't accidentally packaged.
rm -rf "openssl-${OPENSSL_VERSION}" "openssl-${OPENSSL_VERSION}.tar.gz"
