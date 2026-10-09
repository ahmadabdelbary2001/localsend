#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
#
# Build script used by clickable. Maps $ARCH to a Rust target triple,
# builds the binary, and stages it into the click install root.

set -euo pipefail

: "${ARCH:?ARCH not set by clickable}"
: "${INSTALL_DIR:?INSTALL_DIR not set by clickable}"

# The UT SDK image ships Rust at /opt/rust. Prefer it; fall back to
# the standard rustup location otherwise.
if [ -d /opt/rust/cargo/bin ]; then
  export CARGO_HOME="${CARGO_HOME:-/opt/rust/cargo}"
  export RUSTUP_HOME="${RUSTUP_HOME:-/opt/rust/rustup}"
  export PATH="$CARGO_HOME/bin:$PATH"
fi
if [ -d "$HOME/.cargo/bin" ]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found in PATH: $PATH" >&2
  exit 1
fi

echo "Using cargo: $(command -v cargo)"
cargo --version
rustup --version || true

case "$ARCH" in
  arm64) RUST_TARGET=aarch64-unknown-linux-gnu ;;
  armhf) RUST_TARGET=armv7-unknown-linux-gnueabihf ;;
  amd64) RUST_TARGET=x86_64-unknown-linux-gnu ;;
  *) echo "Unsupported ARCH: $ARCH" >&2; exit 1 ;;
esac

echo "Building for $ARCH (Rust target: $RUST_TARGET)"

rustup target add "$RUST_TARGET"

cargo build --release --target "$RUST_TARGET" --manifest-path Cargo.toml

mkdir -p "${INSTALL_DIR}/usr/bin"
cp "target/${RUST_TARGET}/release/localsend-ubuntu-touch" \
   "${INSTALL_DIR}/usr/bin/"

mkdir -p "${INSTALL_DIR}/apparmor"
cp apparmor/localsend-ubuntu-touch.apparmor \
   "${INSTALL_DIR}/apparmor/"
cp localsend-ubuntu-touch.desktop \
   "${INSTALL_DIR}/"

mkdir -p "${INSTALL_DIR}/qml"
cp -r qml/* "${INSTALL_DIR}/qml/"

if [ -d "assets" ]; then
  mkdir -p "${INSTALL_DIR}/assets"
  cp -r assets/* "${INSTALL_DIR}/assets/" 2>/dev/null || true
fi

echo "Staged into ${INSTALL_DIR}"
ls -la "${INSTALL_DIR}/usr/bin/"