# qdrant_edge_flutter

An on-device **Qdrant client for Flutter** — like SQLite, but for vectors.

A real vector store (dense, sparse, and hybrid search with filters and payloads)
that runs entirely on the device: **no server, no API key, no network call.**
Powered by the [`qdrant-edge`](https://crates.io/crates/qdrant-edge) Rust engine
through `dart:ffi`.

- 🧱 **Full client** — shards, upsert, search, hybrid query, payloads, filters,
  field indexes, scroll/retrieve, facets, snapshots.
- 🔍 **On-device embeddings** — BM25 sparse (no model to ship) and optional dense
  semantic (MiniLM) embedders, both in pure Rust.
- 🧠 **Hybrid search** — fuse keyword + meaning with Reciprocal Rank Fusion.
- 📦 **Zero setup** — prebuilt native binaries ship in the package. No Rust
  toolchain needed.
- 📱 Works on **Android** (arm64-v8a, x86_64), **iOS**, and **macOS**.

## Install

```bash
flutter pub add qdrant_edge_flutter
```

## Quick start (text search)

For the common "index text, search text" case, [`TextIndex`] does the embedding
for you:

```dart
import 'package:qdrant_edge_flutter/qdrant_edge_flutter.dart';

final client = QdrantEdge();

// Lexical (BM25). Pass `modelDir:` for hybrid keyword + semantic search.
final index = client.openTextIndex('${dir.path}/notes');

index.add(1, 'the quick brown fox', payload: {'title': 'fox'});
index.add(2, 'stock markets rallied on earnings', payload: {'title': 'finance'});
index.flush();

final hits = index.search('brown fox', limit: 5);
print(hits.first['id']);       // '1'
print(hits.first['score']);    // relevance score
print(hits.first['payload']);  // {'title': 'fox'}

index.close();
```

> Calls are synchronous. For large imports, run them inside an
> [isolate](https://dart.dev/language/isolates) so the UI stays responsive.

## Using the full client

`TextIndex` is a thin convenience over the real API: a [`Shard`] (the vector
store) plus embedders. Use them directly when you want control over the schema,
your own vectors, filters, or hybrid queries. Complex arguments are plain Dart
`Map`/`List` passed to the engine as JSON — the same shape as the Qdrant REST
model.

```dart
final client = QdrantEdge();

// A shard with one dense vector slot.
final shard = client.createShard('${dir.path}/docs', {
  'vectors': {'text': {'size': 384, 'distance': 'Cosine'}},
});

shard.upsert([
  {'id': 1, 'vector': {'text': myEmbedding}, 'payload': {'lang': 'en'}},
  {'id': 2, 'vector': {'text': otherEmbedding}, 'payload': {'lang': 'tr'}},
]);

final hits = shard.search({
  'vector': queryEmbedding,
  'using': 'text',
  'limit': 10,
  'with_payload': true,
  'filter': {'must': [{'key': 'lang', 'match': {'value': 'en'}}]},
});

shard.close();
```

**Distance metrics:** `Cosine` · `Euclid` · `Dot` · `Manhattan`.

### On-device embedders

```dart
final bm25 = client.createBm25();               // sparse, no model needed
final sparse = bm25.embedDocument('quick brown fox'); // {indices, values}

final dense = client.createDense('$dir/model'); // MiniLM (see Hybrid below)
final vector = dense.embed('quick brown fox');  // List<double> (384-d)
```

### Hybrid query (keyword + meaning)

Store both a dense and a sparse (BM25) vector per point, then fuse them:

```dart
final shard = client.createShard('$dir/docs', {
  'vectors': {'dense': {'size': 384, 'distance': 'Cosine'}},
  'sparse_vectors': {'bm25': {'modifier': 'idf'}},
});

shard.upsert([
  {'id': 1, 'vector': {'dense': dense.embed(text), 'bm25': bm25.embedDocument(text)},
   'payload': {'title': 'fox'}},
]);

final hits = shard.query({
  'prefetch': [
    {'query': dense.embed(q), 'using': 'dense', 'limit': 50},
    {'query': bm25.embedQuery(q), 'using': 'bm25', 'limit': 50},
  ],
  'query': {'fusion': 'rrf'},   // or 'dbsf'
  'limit': 10,
  'with_payload': true,
});
```

`TextIndex` with a `modelDir` does exactly this for you.

## API overview

**`QdrantEdge`** (client): `createShard(path, config)`, `loadShard(path)`,
`createBm25()`, `createDense(modelDir)`, `openTextIndex(path, {modelDir})`,
`unpackSnapshot`, `recoverPartialSnapshot`.

**`Shard`**: `upsert`, `deletePoints`, `search`, `query`, `retrieve`, `scroll`,
`count`, `info`, `facet`, `setPayload` / `overwritePayload` / `deletePayload` /
`clearPayload`, `createFieldIndex` / `deleteFieldIndex`, `createVectorName` /
`deleteVectorName`, `setHnswConfig` / `setVectorHnswConfig` /
`setOptimizersConfig`, `snapshotManifest`, `flush`, `optimize`, `close`.

**`Bm25`**: `embedQuery`, `embedDocument`, `close`.
**`Dense`**: `embed`, `close`.
**`TextIndex`**: `add`, `search`, `count`, `flush`, `close`.

Errors surface as `QdrantEdgeException` with the message from the engine.

## The dense model

Dense (semantic) search needs an `all-MiniLM-L6-v2`-style model folder containing
`config.json`, `tokenizer.json` and `model.safetensors` (384-d). Ship it as app
assets and copy it to a real path on first launch, then pass that path to
`createDense` / `openTextIndex(modelDir: ...)`.

> The model adds ~90 MB of assets and a one-time load at startup. Use an
> fp16/quantized model to shrink it. BM25-only search needs no model.

## Notes

- `qdrant-edge` is in **beta** — confirm redistribution terms before publishing a
  build of this package publicly.
- The package bundles prebuilt binaries for Android, iOS and macOS, so consumers
  need no Rust toolchain.

## Building from source (contributors)

Only needed to regenerate the native binaries. Requires **nightly Rust** (pinned
via `rust/rust-toolchain.toml`, because `qdrant-edge` uses unstable features).

```bash
# iOS  → ios/Frameworks/QdrantEdgeFFI.xcframework
rustup toolchain install nightly
sh scripts/build-ios.sh

# Android → android/src/main/jniLibs/<abi>/libqdrant_edge_flutter.so (arm64-v8a, x86_64)
cargo install cargo-ndk          # plus the NDK via Android Studio → SDK Manager
sh scripts/build-android.sh

# macOS → macos/Libraries/libqdrant_edge_flutter.a
sh scripts/build-macos.sh
```

Want a smaller, BM25-only build? Compile with `--no-default-features` to drop the
dense model runtime.

## Credits

The Rust C ABI is adapted from
[rust-dd/react-native-qdrant-edge](https://github.com/rust-dd/react-native-qdrant-edge)
(MIT) — see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

MIT — see [LICENSE](LICENSE).
