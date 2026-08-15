# Changelog

## 0.2.0

- Engine upgraded to `qdrant-edge` 0.8.0; the vendored C ABI is re-synced with
  `qdrant-edge-ffi` 0.4.0.
- `Shard.queryGroups` — group query results by a payload field (`group_by`,
  `limit` groups, `group_size` hits per group), with payload/vector hydration.
- `Shard.searchMatrix` — sample points and return each sample's nearest
  neighbors, for on-device dedup and clustering.
- Search params (`hnsw_ef`, `exact`, `quantization`, `indexed_only`, ACORN,
  sparse IDF corpus) accepted on search, query, and prefetch via `params`.
- `scroll` accepts `order_by` to walk an indexed payload field in either
  direction.
- New filter conditions: `match: {prefix|phrase|text_any}`, plus `has_vector`
  and `slice`.
- `createFieldIndex` also takes a schema `Map`
  (`{'type': 'text', 'phrase_matching': true}`), not just a bare type name —
  needed to build the text index the `phrase` condition requires.
- `info()` now reports `payload_schema` (indexed fields, data type, point count).
- BM25 stemming can be turned off explicitly with `{'stemmer': {'type': 'none'}}`.
- Shard config accepts `max_search_threads` / `search_pool_core` to size the
  parallel per-segment read pool.
- `TextIndex.searchGroups` for the text-first flow; `TextIndex.search` takes
  `params`.
- `flush()` now raises `QdrantEdgeException` instead of panicking in Rust.
- Native binaries rebuilt for iOS, Android and macOS with the new symbols.

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
