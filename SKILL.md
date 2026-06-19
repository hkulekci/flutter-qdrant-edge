---
name: qdrant-edge-flutter
description: >-
  On-device vector search for Flutter via the qdrant_edge_flutter plugin (a
  dart:ffi wrapper around the qdrant-edge Rust crate). Use when building Flutter
  apps that need fully offline, private search over local data — lexical (BM25),
  semantic (dense MiniLM), or hybrid (RRF) — with no server and no network.
  Covers install (git/path), the nightly-Rust native build, the Dart API,
  payload filtering/delete, and iOS/Android/macOS packaging gotchas.
---

# qdrant_edge_flutter

A Flutter FFI plugin that embeds the [`qdrant-edge`](https://crates.io/crates/qdrant-edge)
Rust vector engine. Text in → ranked results out, entirely on device. Think
"SQLite for vectors": in-process, file-backed, no daemon, no network.

Repo: https://github.com/hkulekci/flutter-qdrant-edge

## What it does

- **Lexical search (BM25):** built into qdrant-edge; no model, no download.
- **Semantic search (dense):** optional, via a pure-Rust `candle` MiniLM
  embedder (no ONNX Runtime). Enabled by passing a model directory.
- **Hybrid:** when a model is loaded, queries fuse BM25 + dense with
  Reciprocal Rank Fusion (RRF).
- Payload storage (JSON), filtered delete, count, flush, persistence.

## Architecture (how to reason about it)

```
Dart (QdrantEdge)  ──dart:ffi──▶  Rust C ABI (qe_open/qe_add/qe_search/…)
                                       │  EdgeBm25 (sparse) + candle MiniLM (dense)
                                       ▼
                                   EdgeShard  (qdrant-edge: store + HNSW + search)
                                       ▼
                                   on-disk shard directory (app sandbox)
```

- The C ABI lives in `rust/src/lib.rs`; the safe wrapper in `rust/src/core.rs`;
  the dense embedder in `rust/src/embed.rs` (cargo feature `dense`, on by default).
- Dart loads symbols with `DynamicLibrary.process()` (iOS/macOS, static lib) or
  `DynamicLibrary.open('libqdrant_edge_flutter.so')` (Android).

## Install

Git dependency (uses the prebuilt native artifacts committed to the repo):

```yaml
dependencies:
  qdrant_edge_flutter:
    git:
      url: https://github.com/hkulekci/flutter-qdrant-edge.git
```

Or a local path during development:

```yaml
dependencies:
  qdrant_edge_flutter:
    path: ../flutter-qdrant-edge
```

### Building the native library (only if not using prebuilt artifacts)

Requires **nightly Rust** — `qdrant-edge` uses unstable features; the crate pins
it via `rust/rust-toolchain.toml`. The build scripts `cd` into `rust/` so that
pin is honored (don't run cargo with `--manifest-path` from elsewhere, or it
falls back to stable and fails with `array_windows`).

```bash
rustup toolchain install nightly
sh scripts/build-ios.sh       # → ios/Frameworks/qdrant_edge_flutter.xcframework
sh scripts/build-macos.sh     # → macos/Libraries/libqdrant_edge_flutter.a
cargo install cargo-ndk
sh scripts/build-android.sh   # → android/src/main/jniLibs/<abi>/libqdrant_edge_flutter.so
```

## Dart API

```dart
import 'package:qdrant_edge_flutter/qdrant_edge_flutter.dart';

// Open / create. Pass modelDir for hybrid semantic search (a dir with
// config.json + tokenizer.json + model.safetensors, all-MiniLM-L6-v2 style).
final db = QdrantEdge.open('${dir.path}/notes', modelDir: '${dir.path}/model');

// Upsert: id (int), text (BM25 + dense embedded in Rust), optional JSON payload.
db.add(1, 'the quick brown fox', payload: {'doc': 'a.pdf', 'page': 3});

// Search → List<QdrantHit> { id, score, payload? }.
final hits = db.search('brown fox', limit: 10);

// Delete by id, or by payload filter (robust for "delete a whole document").
db.delete(1);
db.deleteByFilter({'must': [{'key': 'doc', 'match': {'value': 'a.pdf'}}]});

db.count();      // number of points
db.flush();      // persist
db.close();      // release
```

Notes:
- Calls are **synchronous**; for large ingests run them in an isolate.
- Re-adding the same `id` overwrites (upsert).
- Without `modelDir`, search is BM25-only; with it, hybrid (RRF).
- `score` is BM25 score for lexical, or a small RRF score (~1/(60+rank)) for
  hybrid — use it for ranking, not as a 0–1 confidence.

## Gotchas an assistant should know

- **Nightly Rust is mandatory.** Stable fails (`array_windows`).
- **iOS dead-stripping:** the `qe_*` C symbols are referenced from a keepalive
  (and the host app should keep a reference) so the linker doesn't strip them —
  Dart resolves them at runtime via `dlsym`.
- **iOS static-linkage conflict (important):** if the app also pulls in static
  binary pods that force `use_frameworks! :linkage => :static` (e.g. MediaPipe
  via `flutter_gemma`, TensorFlowLite), the Rust static lib's bundled C deps
  (zstd, lz4) collide ("duplicate symbols") and/or `qe_*` get stripped. Prefer
  dynamic frameworks (`use_frameworks!`); if a static-binary dependency is
  required, isolate this engine in its own dynamic framework.
- **Dense model files:** all-MiniLM-L6-v2 needs `config.json`, `tokenizer.json`,
  `model.safetensors`; ship them as assets and copy to a real path on first run
  (Rust mmaps the weights). 384-dim, Cosine.
- **Storage:** point the shard dir at the app's private support directory so it
  is removed on uninstall and invisible to other apps.
- **qdrant-edge is private beta** — confirm redistribution terms before shipping.

## Common tasks → where to look

- Change/extend the C ABI: `rust/src/lib.rs` + `rust/include/qdrant_edge_flutter.h`
  + the iOS/macOS `Classes/qdrant_edge_flutter_keepalive.c` + Dart
  `lib/src/bindings.dart`.
- Add a query type (filter, MMR, recommend): `rust/src/core.rs` (`QueryRequest`).
- Re-export a qdrant-edge type: everything is re-exported at the crate root
  (`pub use edge::*`); the BM25 embedder is at `qdrant_edge::bm25_embed`.
