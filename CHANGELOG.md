# Changelog

## 0.1.0

- Initial release: an on-device Qdrant client for Flutter via `dart:ffi` over the
  `qdrant-edge` Rust engine.
- `QdrantEdge` client: `createShard` / `loadShard`, `createBm25`, `createDense`,
  `openTextIndex`, snapshot helpers.
- `Shard` with the full surface: `upsert`, `deletePoints`, `search`, `query`
  (prefetch + RRF/DBSF fusion), `retrieve`, `scroll`, `count`, `info`, `facet`,
  payload ops, field indexes, runtime named vectors, HNSW/optimizer config,
  `flush`, `optimize`, `close`. Complex arguments are plain Dart `Map`/`List`
  passed to the engine as JSON.
- On-device embedders: `Bm25` (sparse, no model to ship) and `Dense` (MiniLM via
  `candle`, optional). `TextIndex` convenience for the add-text/search-text flow
  (lexical, or hybrid with a model).
- Prebuilt native binaries ship in the package (iOS dynamic
  `QdrantEdgeFFI.xcframework`, Android `.so` for arm64-v8a + x86_64, macOS `.a`)
  — no Rust toolchain required to consume the plugin.
- Platforms: Android, iOS, macOS.
