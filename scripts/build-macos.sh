#!/bin/bash
set -euo pipefail
# Build the Rust static library for macOS (host arch) for desktop dev/testing.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUST_DIR="$SCRIPT_DIR/../rust"
OUT="$SCRIPT_DIR/../macos/Libraries/libqdrant_edge_flutter.a"
echo "==> Building macOS staticlib (release)..."
# Run from the crate dir so rust-toolchain.toml (nightly) is honored.
cd "$RUST_DIR"
cargo rustc --release --crate-type staticlib
mkdir -p "$(dirname "$OUT")"
cp "$RUST_DIR/target/release/libqdrant_edge_flutter.a" "$OUT"
echo "==> Done: $OUT"
