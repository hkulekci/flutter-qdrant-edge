#!/bin/bash
set -euo pipefail

# Build the Rust engine as a DYNAMIC framework xcframework for iOS.
#
# Why dynamic: when the host app also links static-binary pods (e.g. MediaPipe/
# TensorFlow via flutter_gemma) it must use `use_frameworks! :linkage => :static`,
# which dead-strips our qe_* symbols and clashes on the Rust lib's bundled C deps
# (zstd, lz4). Shipping a self-contained dynamic framework that exports ONLY the
# qe_* C ABI isolates everything: no stripping, no duplicate symbols.
#
# How: build the staticlib (Rust), then `clang -dynamiclib -force_load` it with
# an -exported_symbols_list so only qe_* is exported and the bundled C deps stay
# private to the framework.
#
# Requires nightly Rust (rust-toolchain.toml).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUST_DIR="$SCRIPT_DIR/../rust"
OUT_DIR="$SCRIPT_DIR/../ios/Frameworks"
FW=QdrantEdgeFFI                  # dynamic framework + binary name (must differ
                                  # from the pod name to avoid "multiple commands
                                  # produce" under use_frameworks!)
LIB=libqdrant_edge_flutter.a
MIN_IOS=16.0

cd "$RUST_DIR"
for t in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  rustup target add "$t" 2>/dev/null || true
done
echo "==> Building Rust staticlib for iOS targets..."
for t in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  echo "  -> $t"
  cargo rustc --release --target "$t" --crate-type staticlib
done

EXPORTED="$(mktemp)"
cat > "$EXPORTED" <<'SYMS'
_qe_open
_qe_add
_qe_search
_qe_delete
_qe_delete_by_filter
_qe_count
_qe_flush
_qe_close
_qe_last_error
_qe_string_free
SYMS

SDK_DEVICE="$(xcrun --sdk iphoneos --show-sdk-path)"
SDK_SIM="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SYSLIBS=(-lc++ -framework Foundation -framework Security -framework CoreFoundation)

# dylib <out> <target-triple> <sysroot> <staticlib...>
dylib() {
  local out="$1" triple="$2" sysroot="$3"; shift 3
  local force=()
  for a in "$@"; do force+=(-Wl,-force_load,"$a"); done
  clang -dynamiclib -target "$triple" -isysroot "$sysroot" \
    "${force[@]}" \
    -Wl,-exported_symbols_list,"$EXPORTED" \
    -install_name "@rpath/$FW.framework/$FW" \
    "${SYSLIBS[@]}" -o "$out"
}

TMP="$(mktemp -d)"
echo "==> Linking dynamic framework binaries..."
dylib "$TMP/dev" "arm64-apple-ios$MIN_IOS" "$SDK_DEVICE" \
  "$RUST_DIR/target/aarch64-apple-ios/release/$LIB"
dylib "$TMP/sim_arm" "arm64-apple-ios$MIN_IOS-simulator" "$SDK_SIM" \
  "$RUST_DIR/target/aarch64-apple-ios-sim/release/$LIB"
dylib "$TMP/sim_x86" "x86_64-apple-ios$MIN_IOS-simulator" "$SDK_SIM" \
  "$RUST_DIR/target/x86_64-apple-ios/release/$LIB"
lipo -create "$TMP/sim_arm" "$TMP/sim_x86" -o "$TMP/sim"

# mkfw <framework-dir> <binary> <platform>
mkfw() {
  local dir="$1" bin="$2" platform="$3"
  mkdir -p "$dir"
  cp "$bin" "$dir/$FW"
  cat > "$dir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$FW</string>
  <key>CFBundleIdentifier</key><string>tech.qdrant.qdrantEdgeFlutter</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$FW</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>$MIN_IOS</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>
</dict></plist>
PLIST
}

echo "==> Assembling frameworks + xcframework..."
mkfw "$TMP/device/$FW.framework" "$TMP/dev" iPhoneOS
mkfw "$TMP/simulator/$FW.framework" "$TMP/sim" iPhoneSimulator

mkdir -p "$OUT_DIR"
rm -rf "$OUT_DIR/$FW.xcframework"
xcodebuild -create-xcframework \
  -framework "$TMP/device/$FW.framework" \
  -framework "$TMP/simulator/$FW.framework" \
  -output "$OUT_DIR/$FW.xcframework"

rm -rf "$TMP"
echo "==> Done: $OUT_DIR/$FW.xcframework (dynamic, exports qe_* only)"
