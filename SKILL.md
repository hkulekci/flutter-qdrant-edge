---
name: qdrant-edge-flutter
description: >-
  On-device Qdrant client for Flutter via the qdrant_edge_flutter plugin (a
  dart:ffi wrapper around the qdrant-edge Rust engine). Use when building Flutter
  apps that need a fully offline, private vector store — dense, sparse (BM25),
  and hybrid (RRF) search with payloads, filters, and field indexes — with no
  server and no network. Covers install, the Dart client API, on-device
  embedders, the native build, and iOS/Android/macOS packaging gotchas.
---

# qdrant_edge_flutter

A Flutter FFI plugin that embeds the [`qdrant-edge`](https://crates.io/crates/qdrant-edge)
Rust vector engine as an on-device **Qdrant client**. In-process, file-backed,
no daemon, no network — "SQLite for vectors".

Repo: https://github.com/hkulekci/flutter-qdrant-edge

## What it does

- **Vector store:** shards, upsert, search, hybrid `query` (prefetch + fusion),
  retrieve, scroll, count, info, facet, payload ops, filters, field indexes,
  runtime named vectors, HNSW/optimizer config, snapshots.
- **On-device embedders:** BM25 sparse (built into qdrant-edge, no model) and an
  optional pure-Rust `candle` MiniLM dense embedder (no ONNX Runtime).
- **Hybrid:** fuse dense + BM25 with Reciprocal Rank Fusion (RRF) or DBSF.

Complex arguments cross the FFI as JSON strings; the Dart API takes plain
`Map`/`List`, mirroring the Qdrant REST model.

## Architecture (how to reason about it)

```
Dart (QdrantEdge / Shard / Bm25 / Dense)  ──dart:ffi──▶  C ABI (qe_shard_*, qe_bm25_*, qe_dense_*)
                                                              ▼
                                                   EdgeShard (qdrant-edge: store + HNSW + search)
                                                              ▼
                                                   on-disk shard directory (app sandbox)
```

- The C ABI is the vendored, JSON-forwarding `qdrant-edge-ffi` crate (MIT, from
  rust-dd/react-native-qdrant-edge), laid out as modules under `rust/src/`
  (`lifecycle.rs`, `points.rs`, `search_query.rs`, `payload.rs`, `field_index.rs`,
  `retrieve_scroll.rs`, `facet.rs`, `snapshot.rs`, `config.rs`, `info.rs`,
  `bm25.rs`, `serde_types.rs`). Our additions: `embed.rs` + `dense.rs` (the
  candle dense embedder, cargo feature `dense`, on by default). The C header is
  cbindgen-generated at `rust/include/qdrant_edge_flutter.h`.
- Dart loads symbols with `DynamicLibrary.process()` (iOS/macOS) or
  `DynamicLibrary.open('libqdrant_edge_flutter.so')` (Android).
- **iOS** ships the engine as a self-contained **dynamic framework**
  (`QdrantEdgeFFI.framework`) that exports only the `qe_*` C ABI (bundled C deps
  like zstd stay private). This isolates it from static-binary pods (e.g.
  MediaPipe/TFLite via flutter_gemma) under `use_frameworks! :linkage => :static`.
  The framework name differs from the pod name on purpose, else `use_frameworks!`
  errors with "multiple commands produce …framework".
- **macOS/iOS** also compile `Classes/qdrant_edge_flutter_keepalive.c`, which
  references one `qe_*` symbol per FFI module so the static archive isn't
  dead-stripped (macOS links the `.a` directly). Keep it in sync with the symbol
  set when the C ABI changes.

## Install

```bash
flutter pub add qdrant_edge_flutter
```

Or from git / local path during development:

```yaml
dependencies:
  qdrant_edge_flutter:
    git: { url: https://github.com/hkulekci/flutter-qdrant-edge.git }
    # or: path: ../flutter-qdrant-edge
```

Prebuilt native binaries ship in the package (iOS xcframework, Android `.so` for
arm64-v8a + x86_64, macOS `.a`), so consumers need no Rust toolchain.

## Dart API

```dart
import 'package:qdrant_edge_flutter/qdrant_edge_flutter.dart';

final client = QdrantEdge();

// Easy path: TextIndex embeds for you (lexical; pass modelDir for hybrid).
final index = client.openTextIndex('${dir.path}/notes'); // or modelDir: '$dir/model'
index.add(1, 'the quick brown fox', payload: {'doc': 'a.pdf'});
final hits = index.search('brown fox', limit: 10); // List<Map>: {id, score, payload}
index.close();

// Full client: your own schema + vectors.
final shard = client.createShard('$dir/docs', {
  'vectors': {'dense': {'size': 384, 'distance': 'Cosine'}},
  'sparse_vectors': {'bm25': {'modifier': 'idf'}},
});
final bm25 = client.createBm25();
final dense = client.createDense('$dir/model');
shard.upsert([
  {'id': 1, 'vector': {'dense': dense.embed(t), 'bm25': bm25.embedDocument(t)},
   'payload': {'doc': 'a.pdf'}},
]);
final out = shard.query({
  'prefetch': [
    {'query': dense.embed(q), 'using': 'dense', 'limit': 50},
    {'query': bm25.embedQuery(q), 'using': 'bm25', 'limit': 50},
  ],
  'query': {'fusion': 'rrf'},
  'limit': 10,
  'with_payload': true,
});
shard.deletePoints([1]);
shard.setPayload({'payload': {'tag': 'x'}, 'filter': {'must': [{'key': 'doc', 'match': {'value': 'a.pdf'}}]}});
```

Notes:
- Calls are **synchronous**; for large ingests run them in an isolate.
- Re-upserting the same `id` overwrites. Ids are u64 or UUID strings.
- Errors throw `QdrantEdgeException` with the engine's message.
- `score` for hybrid is a small RRF score (~1/(60+rank)) — use for ranking, not
  as a 0–1 confidence.

## Gotchas an assistant should know

- **Nightly Rust is mandatory** to build the engine (`qdrant-edge` uses unstable
  features; pinned via `rust/rust-toolchain.toml`, edition 2024). Build scripts
  `cd` into `rust/` so the pin is honored.
- **Android: 64-bit ABIs only** (arm64-v8a, x86_64). The 32-bit ABIs
  (armeabi-v7a, x86) can't build qdrant-edge's bundled SIMD C deps.
- **iOS dynamic framework `QdrantEdgeFFI`** is built by `clang -dynamiclib
  -force_load <staticlib> -exported_symbols_list <qe_*>`; the symbol list is
  derived from the built lib via `nm` in `build-ios.sh`. Keep the framework name
  different from the pod, and do not bake a stale `-force_load …/.a` into the
  Runner project.
- **keepalive.c** (ios + macos `Classes/`) must reference current `qe_*` symbols
  — stale refs (e.g. the removed `qe_open`) break linking with undefined symbols.
- **Dense model files:** all-MiniLM-L6-v2 needs `config.json`, `tokenizer.json`,
  `model.safetensors` (384-d, Cosine); ship as assets, copy to a real path on
  first run (Rust mmaps the weights). BM25-only needs no model.
- **qdrant-edge is in beta** — confirm redistribution terms before shipping.

## Common tasks → where to look

- Change/extend the C ABI: the relevant `rust/src/<module>.rs` + re-export in
  `rust/src/lib.rs`, regenerate `rust/include/qdrant_edge_flutter.h` with
  cbindgen, update `Classes/qdrant_edge_flutter_keepalive.c` and Dart
  `lib/src/bindings.dart` + the high-level wrapper in `lib/qdrant_edge_flutter.dart`.
- Request/response JSON shapes (points, search, query, filters): `rust/src/serde_types.rs`.
- Dense embedder: `rust/src/embed.rs` (model) + `rust/src/dense.rs` (C ABI).
- Rebuild binaries: `scripts/build-ios.sh`, `build-android.sh`, `build-macos.sh`.
