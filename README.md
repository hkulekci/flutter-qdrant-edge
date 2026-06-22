# qdrant_edge_flutter

On-device vector search for Flutter — like SQLite, but for vectors.

Add text, get back ranked results. Everything runs locally on the device:
**no server, no API key, no network call.** Powered by the
[`qdrant-edge`](https://crates.io/crates/qdrant-edge) Rust engine through
`dart:ffi`.

- 🔍 **Lexical search (BM25)** out of the box — text embedding runs in Rust, so
  there is nothing to download.
- 🧠 **Hybrid search (optional)** — combine keyword matching with semantic
  meaning using a small on-device model.
- 📦 **Zero setup** — prebuilt native binaries ship inside the package. No Rust
  toolchain needed.
- 📱 Works on **Android, iOS, and macOS**.

## Install

```bash
flutter pub add qdrant_edge_flutter
```

## Quick start

```dart
import 'package:qdrant_edge_flutter/qdrant_edge_flutter.dart';

// Open (or create) a database in a folder on the device.
final db = QdrantEdge.open('${dir.path}/notes');

// Add some documents.
db.add(1, 'the quick brown fox', payload: {'title': 'fox'});
db.add(2, 'stock markets rallied on earnings', payload: {'title': 'finance'});

// Search.
final hits = db.search('brown fox', limit: 5);
print(hits.first.id);       // 1
print(hits.first.score);    // relevance score
print(hits.first.payload);  // {'title': 'fox'}

db.close();
```

That's it — the text is embedded and ranked entirely on the device.

> Calls are synchronous. For large imports, run them inside an
> [isolate](https://dart.dev/language/isolates) so the UI stays responsive.

## API

| Method                              | What it does                                |
|-------------------------------------|---------------------------------------------|
| `QdrantEdge.open(path)`             | Open or create a database at a folder path  |
| `db.add(id, text, {payload})`       | Add or update a document                    |
| `db.search(query, {limit})`         | Return results ranked by relevance          |
| `db.delete(id)`                     | Remove a document                           |
| `db.deleteByFilter(filter)`         | Remove documents matching a payload filter  |
| `db.count()`                        | Number of stored documents                  |
| `db.flush()`                        | Persist pending writes to disk              |
| `db.close()`                        | Release the database                        |

## Hybrid search (keyword + meaning)

By default search matches on **keywords** (BM25). To also match on **meaning**
(so "car" can find "automobile"), pass a model folder when opening the database:

```dart
// Keyword only:
final db = QdrantEdge.open('$dir/notes');

// Hybrid: keyword + semantic, automatically combined:
final db = QdrantEdge.open('$dir/notes', modelDir: '$dir/model');
```

The model folder must contain `config.json`, `tokenizer.json` and
`model.safetensors` for an `all-MiniLM-L6-v2`-style model (384 dimensions). Ship
those as app assets and copy them to a real path on first launch — the
[`example/`](example/) app shows how.

> The model adds ~90 MB of assets and a one-time load at startup. Use an
> fp16/quantized model to shrink it.

## Notes

- `qdrant-edge` is in **beta** — confirm redistribution terms before publishing
  a build of this package publicly.
- The package bundles prebuilt binaries for Android, iOS and macOS, so consumers
  need no Rust toolchain.

## Building from source (contributors)

You only need this to regenerate the native binaries. It requires **nightly
Rust** (pinned via `rust/rust-toolchain.toml`, because `qdrant-edge` uses
unstable features).

```bash
# iOS  → ios/Frameworks/QdrantEdgeFFI.xcframework
rustup toolchain install nightly
sh scripts/build-ios.sh

# Android → android/src/main/jniLibs/<abi>/libqdrant_edge_flutter.so
cargo install cargo-ndk          # plus the NDK via Android Studio → SDK Manager
sh scripts/build-android.sh

# macOS → macos/Libraries/libqdrant_edge_flutter.a
sh scripts/build-macos.sh
```

Want a smaller, keyword-only build? Compile with `--no-default-features` to drop
the semantic model.

## License

MIT — see [LICENSE](LICENSE).
