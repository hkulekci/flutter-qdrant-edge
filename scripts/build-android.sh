#!/bin/bash
set -euo pipefail

# Build the Rust cdylib for Android and drop the .so files into
# android/src/main/jniLibs/<abi>/, which Flutter bundles automatically.
#
# Requires: nightly Rust, the Android NDK, and cargo-ndk.
#   cargo install cargo-ndk
#   rustup target add aarch64-linux-android armv7-linux-androideabi \
#                     x86_64-linux-android i686-linux-android

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUST_DIR="$SCRIPT_DIR/../rust"
OUT_DIR="$SCRIPT_DIR/../android/src/main/jniLibs"

# Locate the NDK if not already exported.
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  for c in "$HOME/Library/Android/sdk/ndk"/*/ "$HOME/Android/Sdk/ndk"/*/ \
           "${ANDROID_HOME:-/nonexistent}/ndk"/*/ "${ANDROID_SDK_ROOT:-/nonexistent}/ndk"/*/; do
    [ -d "$c" ] && ANDROID_NDK_HOME="${c%/}" && break
  done
fi
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  echo "ERROR: Android NDK not found. Set ANDROID_NDK_HOME or install via Android Studio." >&2
  exit 1
fi
export ANDROID_NDK_HOME
echo "==> NDK: $ANDROID_NDK_HOME"

if ! command -v cargo-ndk >/dev/null 2>&1; then
  echo "==> Installing cargo-ndk..."
  cargo install cargo-ndk
fi

TARGETS="aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android"

echo "==> Building Android ABIs (release)..."
# cd first so rust-toolchain.toml (nightly) is honored for both `rustup target
# add` and the build (otherwise targets land on stable but the build is nightly).
cd "$RUST_DIR"
for t in $TARGETS; do
  rustup target add "$t" 2>/dev/null || true
done

# cargo-ndk maps targets to ABI folder names and writes .so into -o/<abi>/.
cargo ndk \
  -t arm64-v8a -t armeabi-v7a -t x86_64 -t x86 \
  -o "$OUT_DIR" \
  build --release

echo "==> Done. Libraries in $OUT_DIR/<abi>/libqdrant_edge_flutter.so"
