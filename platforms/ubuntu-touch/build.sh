#!/bin/bash
# (الصق محتوى build.sh هنا)
#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
#
# Unified build script used by clickable (local + CI).
# Maps the clickable $ARCH to a Rust target triple, builds the
# binary, and stages it into the click install root.

set -euo pipefail

# clickable provides:
#   $ARCH               - arm64 | armhf | amd64
#   $INSTALL_DIR        - click root staging dir
#   $CLICKABLE_BUILD_DIR - build/ directory
: "${ARCH:?ARCH not set by clickable}"
: "${INSTALL_DIR:?INSTALL_DIR not set by clickable}"

case "$ARCH" in
  arm64) RUST_TARGET=aarch64-unknown-linux-gnu ;;
  armhf) RUST_TARGET=armv7-unknown-linux-gnueabihf ;;
  amd64) RUST_TARGET=x86_64-unknown-linux-gnu ;;
  *) echo "Unsupported ARCH: $ARCH" >&2; exit 1 ;;
esac

echo "Building for $ARCH (Rust target: $RUST_TARGET)"

CARGO="${HOME}/.cargo/bin/cargo"
if [ ! -x "$CARGO" ]; then
  echo "cargo not found at $CARGO" >&2
  exit 1
fi

# Ensure the target is installed.
"${HOME}/.cargo/bin/rustup" target add "$RUST_TARGET" >/dev/null

# Build.
"$CARGO" build --release --target "$RUST_TARGET" --manifest-path Cargo.toml

# Stage the binary.
mkdir -p "${INSTALL_DIR}/usr/bin"
cp "target/${RUST_TARGET}/release/localsend-ubuntu-touch" \
   "${INSTALL_DIR}/usr/bin/"

# Stage apparmor + desktop file at the paths the manifest expects.
mkdir -p "${INSTALL_DIR}/apparmor"
cp apparmor/localsend-ubuntu-touch.apparmor \
   "${INSTALL_DIR}/apparmor/"
cp localsend-ubuntu-touch.desktop \
   "${INSTALL_DIR}/"

# Ship QML sources for debugability (the binary embeds them via qrc!).
mkdir -p "${INSTALL_DIR}/qml"
cp -r qml/* "${INSTALL_DIR}/qml/"

# Ship assets referenced from QML (if any).
if [ -d "assets" ]; then
  mkdir -p "${INSTALL_DIR}/assets"
  cp -r assets/* "${INSTALL_DIR}/assets/" 2>/dev/null || true
fi

echo "Staged into ${INSTALL_DIR}"
ls -la "${INSTALL_DIR}/usr/bin/"