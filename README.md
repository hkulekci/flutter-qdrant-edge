# qdrant_edge_flutter

On-device vector search for Flutter, powered by the [`qdrant-edge`](https://crates.io/crates/qdrant-edge)
Rust crate. Text goes in, ranked results come out — **BM25 text embedding runs
inside Rust**, so there is no model download and no network call. Everything is
local to the device, like SQLite for vectors.

```dart
final db = QdrantEdge.open('${dir.path}/notes');
db.add(1, 'the quick brown fox', payload: {'title': 'fox'});
db.add(2, 'stock markets rallied on earnings', payload: {'title': 'finance'});

final hits = db.search('brown fox', limit: 5);
// hits[0].id == '1', with score and payload

db.close();
```

## How it works

```
Dart (QdrantEdge)  ──dart:ffi──▶  Rust C ABI (qe_open/qe_add/qe_search/...)
                                       │
                                  ┌────┴─────┐
                                  │ EdgeBm25 │  text → sparse vector (TF/IDF)
                                  └────┬─────┘
                                       ▼
                                  EdgeShard  (qdrant-edge: store + HNSW + search)
                                       ▼
                                  on-disk shard directory
```

Each database is created with a single **sparse** vector slot using the IDF
modifier. `add()` BM25-embeds the document (term-frequency weights); `search()`
BM25-embeds the query and the shard scores with inverse-document-frequency —
together that is the BM25 ranking, computed entirely on device.

> This first version ships **lexical (BM25)** search. For semantic search you
> can store your own dense vectors instead — see "Going dense" below.

## Project layout

```
qdrant_edge_flutter/
  rust/                     Rust crate (the native engine)
    src/core.rs             safe wrapper: open/add/search/delete/count/flush (+ test)
    src/lib.rs              C ABI exported to Dart
    src/{error,ffi}.rs      last-error + string helpers
    include/qdrant_edge_flutter.h   C header (matches lib.rs)
    rust-toolchain.toml     pins nightly (qdrant-edge needs unstable features)
  lib/
    qdrant_edge_flutter.dart   high-level Dart API (use this)
    src/bindings.dart          raw dart:ffi bindings
  ios/                      podspec + xcframework (built by script)
  android/                  gradle module + jniLibs (built by script)
  scripts/build-ios.sh      → ios/Frameworks/qdrant_edge_flutter.xcframework
  scripts/build-android.sh  → android/src/main/jniLibs/<abi>/*.so
  example/                  minimal app using the plugin
```

## Building the native library

Both builds need **nightly Rust** (pinned via `rust/rust-toolchain.toml`) because
`qdrant-edge` uses unstable features.

### iOS

```bash
rustup toolchain install nightly
sh scripts/build-ios.sh        # produces ios/Frameworks/qdrant_edge_flutter.xcframework
```

### Android

```bash
cargo install cargo-ndk
# Android Studio → SDK Manager → install "NDK (Side by side)"
sh scripts/build-android.sh    # produces android/src/main/jniLibs/<abi>/libqdrant_edge_flutter.so
```

Then add the plugin to your app's `pubspec.yaml`:

```yaml
dependencies:
  qdrant_edge_flutter:
    path: ../qdrant_edge_flutter
```

## API

| Dart                                   | Description                                  |
|----------------------------------------|----------------------------------------------|
| `QdrantEdge.open(path)`                | open/create a database at a directory path   |
| `db.add(id, text, {payload})`          | upsert a document (BM25-embedded)            |
| `db.search(query, {limit})`            | `List<QdrantHit>` ranked by similarity       |
| `db.delete(id)`                        | remove a point                               |
| `db.count()`                           | number of stored points                      |
| `db.flush()`                           | persist pending writes                       |
| `db.close()`                           | release the handle                           |

Calls are synchronous. For large batch ingests, run them inside an isolate to
keep the UI thread responsive.

## Semantic / hybrid search (dense)

Dense semantic search is **built in** (the `dense` cargo feature, on by default).
Embedding runs in pure Rust via [`candle`](https://crates.io/crates/candle-core)
with a sentence-transformers **MiniLM** model — no ONNX Runtime, no per-platform
native dependency, so it cross-compiles like the rest of the crate.

Pass a model directory to `open` to enable it:

```dart
// Lexical (BM25) only:
final db = QdrantEdge.open('$dir/notes');

// Hybrid (BM25 + semantic, fused with Reciprocal Rank Fusion):
final db = QdrantEdge.open('$dir/notes', modelDir: '$dir/model');
```

The `modelDir` must contain `config.json`, `tokenizer.json` and
`model.safetensors` for an all-MiniLM-L6-v2-style BERT model (384-d). Ship those
as app assets and copy them to a real path on first launch (the example app does
this). With a model loaded, each document stores **both** a BM25 sparse vector
and a dense vector, and `search` runs a hybrid query that RRF-fuses the two — so
it finds matches by keyword *and* by meaning.

Cost: the model adds ~90 MB (fp32) of assets and a one-time load at startup. Use
an fp16/quantized model to shrink it.

## Notes & caveats

- **Nightly toolchain** is required by `qdrant-edge` 0.7.x. The build scripts
  `cd` into `rust/` so `rust-toolchain.toml` (nightly) is honored — don't invoke
  cargo with `--manifest-path` from elsewhere or it falls back to stable.
- Build the `dense`-disabled variant (`--no-default-features`) for a much smaller
  BM25-only library if you don't need semantic search.
- The native static lib is large on disk (LTO archive); the linked binary
  footprint is far smaller. The MiniLM model adds ~90 MB of assets when dense is
  used.
- `qdrant-edge` is in private beta — confirm redistribution terms before
  publishing this package publicly.
