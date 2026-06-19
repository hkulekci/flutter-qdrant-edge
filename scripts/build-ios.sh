#!/bin/bash
set -euo pipefail

# Build the Rust staticlib for iOS (device + simulator) and assemble an
# xcframework consumed by ios/qdrant_edge_flutter.podspec.
#
# Requires nightly Rust (qdrant-edge uses unstable features) and the iOS
# targets; this script installs the targets if missing.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUST_DIR="$SCRIPT_DIR/../rust"
OUT_DIR="$SCRIPT_DIR/../ios/Frameworks"
LIB=libqdrant_edge_flutter.a

TARGETS="aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios"

echo "==> Building iOS targets (release, staticlib only)..."
# iOS only needs the static library; the cdylib crate-type cannot be linked for
# iOS (no dynamic libraries), so override crate-type to staticlib per build.
# cd first so rust-toolchain.toml (nightly) is honored for BOTH `rustup target
# add` and the build — otherwise targets land on the stable toolchain while the
# build uses nightly, and nightly can't find std for them.
cd "$RUST_DIR"
for t in $TARGETS; do
  rustup target add "$t" 2>/dev/null || true
done
for t in $TARGETS; do
  echo "  -> $t"
  cargo rustc --release --target "$t" --crate-type staticlib
done

mkdir -p "$OUT_DIR"
TMP="$(mktemp -d)"
mkdir -p "$TMP/device" "$TMP/sim"

# Device slice (arm64) — keep the same basename in each slice directory.
cp "$RUST_DIR/target/aarch64-apple-ios/release/$LIB" "$TMP/device/$LIB"

# Simulator slice: fat arm64 + x86_64.
lipo -create \
  "$RUST_DIR/target/aarch64-apple-ios-sim/release/$LIB" \
  "$RUST_DIR/target/x86_64-apple-ios/release/$LIB" \
  -output "$TMP/sim/$LIB"

echo "==> Assembling xcframework..."
rm -rf "$OUT_DIR/qdrant_edge_flutter.xcframework"
xcodebuild -create-xcframework \
  -library "$TMP/device/$LIB" -headers "$RUST_DIR/include" \
  -library "$TMP/sim/$LIB"    -headers "$RUST_DIR/include" \
  -output "$OUT_DIR/qdrant_edge_flutter.xcframework"

rm -rf "$TMP"
echo "==> Done: $OUT_DIR/qdrant_edge_flutter.xcframework"
