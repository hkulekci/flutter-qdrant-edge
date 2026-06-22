# Changelog

## 0.1.0

- Initial release.
- On-device vector search for Flutter via `dart:ffi` over the `qdrant-edge` Rust crate.
- Lexical (BM25) search with text embedding computed in Rust — no model download, no network.
- Optional hybrid search (BM25 + dense MiniLM via `candle`) fused with Reciprocal Rank Fusion when a model directory is provided.
- API: `open`, `add`, `search`, `delete`, `deleteByFilter`, `count`, `flush`, `close`.
- Prebuilt native binaries ship in the package (iOS dynamic `QdrantEdgeFFI.xcframework`, Android `.so` per ABI, macOS `.a`) — no Rust toolchain required to consume the plugin.
- Platforms: Android, iOS, macOS.
