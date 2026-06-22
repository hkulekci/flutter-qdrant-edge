/// On-device Qdrant vector search for Flutter, powered by the `qdrant-edge`
/// Rust engine over `dart:ffi`. Everything runs locally — no server, no network.
///
/// [QdrantEdge] is the client/factory: it creates [Shard]s (the vector store)
/// and the on-device embedders ([Bm25] sparse, [Dense] semantic). Complex
/// arguments are plain Dart `Map`/`List` that are passed to the engine as JSON,
/// mirroring the Qdrant request model.
///
/// ```dart
/// final client = QdrantEdge();
/// final shard = client.createShard('${dir.path}/notes', {
///   'vectors': {'dense': {'size': 384, 'distance': 'Cosine'}},
/// });
/// shard.upsert([
///   {'id': 1, 'vector': {'dense': embedding}, 'payload': {'title': 'fox'}},
/// ]);
/// final hits = shard.search({'vector': query, 'using': 'dense', 'limit': 5});
/// shard.close();
/// ```
///
/// For the simple "add text / search text" workflow, see [TextIndex] via
/// [QdrantEdge.openTextIndex].
library qdrant_edge_flutter;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'src/bindings.dart';

/// Thrown when a native call fails. The message comes from Rust.
class QdrantEdgeException implements Exception {
  QdrantEdgeException(this.message);
  final String message;
  @override
  String toString() => 'QdrantEdgeException: $message';
}

String? _takeError(QdrantEdgeBindings b) {
  final p = b.lastError();
  if (p == nullptr) return null;
  try {
    return p.toDartString();
  } finally {
    b.freeString(p);
  }
}

Never _fail(QdrantEdgeBindings b, String op) =>
    throw QdrantEdgeException(_takeError(b) ?? '$op failed');

/// Decode a JSON string result, freeing the native buffer; throw on null.
dynamic _takeJson(QdrantEdgeBindings b, Pointer<Utf8> p, String op) {
  if (p == nullptr) _fail(b, op);
  try {
    return jsonDecode(p.toDartString());
  } finally {
    b.freeString(p);
  }
}

/// The client / factory. Cheap to construct; the native library loads once.
class QdrantEdge {
  QdrantEdge();

  static QdrantEdgeBindings? _cached;

  /// The resolved native bindings (loaded lazily, once per process).
  static QdrantEdgeBindings get bindings =>
      _cached ??= QdrantEdgeBindings(QdrantEdgeBindings.loadLibrary());

  /// Create a new shard at [path]. [config] is an `EdgeConfig` map, e.g.
  /// `{'vectors': {'dense': {'size': 384, 'distance': 'Cosine'}},
  ///   'sparse_vectors': {'bm25': {'modifier': 'idf'}}}`.
  /// The directory is created if needed.
  Shard createShard(String path, Map<String, dynamic> config) {
    Directory(path).createSync(recursive: true);
    return _openShard(path, jsonEncode(config), create: true);
  }

  /// Load an existing shard from [path]. Pass [config] only to override the
  /// stored configuration.
  Shard loadShard(String path, {Map<String, dynamic>? config}) =>
      _openShard(path, config == null ? '' : jsonEncode(config), create: false);

  Shard _openShard(String path, String configJson, {required bool create}) {
    final b = bindings;
    final p = path.toNativeUtf8();
    final c = configJson.toNativeUtf8();
    try {
      final h = create ? b.shardCreate(p, c) : b.shardLoad(p, c);
      if (h == nullptr) _fail(b, create ? 'createShard' : 'loadShard');
      return Shard._(b, h);
    } finally {
      calloc.free(p);
      calloc.free(c);
    }
  }

  /// Construct an on-device BM25 sparse embedder. [config] is an optional
  /// `EdgeBm25Config` map (omit for defaults).
  Bm25 createBm25({Map<String, dynamic>? config}) {
    final b = bindings;
    final c = (config == null ? '' : jsonEncode(config)).toNativeUtf8();
    try {
      final h = b.bm25Create(c);
      if (h == nullptr) _fail(b, 'createBm25');
      return Bm25._(b, h);
    } finally {
      calloc.free(c);
    }
  }

  /// Load an on-device dense (semantic) embedder from [modelDir] — a directory
  /// with `config.json`, `tokenizer.json` and `model.safetensors` (MiniLM-style,
  /// 384-d). Requires the `dense` build of the engine.
  Dense createDense(String modelDir) {
    final b = bindings;
    final m = modelDir.toNativeUtf8();
    try {
      final h = b.denseCreate(m);
      if (h == nullptr) _fail(b, 'createDense');
      return Dense._(b, h);
    } finally {
      calloc.free(m);
    }
  }

  /// Unpack a snapshot archive into a directory.
  void unpackSnapshot(String snapshotPath, String targetPath) {
    final b = bindings;
    final s = snapshotPath.toNativeUtf8();
    final t = targetPath.toNativeUtf8();
    try {
      if (b.unpackSnapshot(s, t) != 0) _fail(b, 'unpackSnapshot');
    } finally {
      calloc.free(s);
      calloc.free(t);
    }
  }

  /// Recover a shard from a partial snapshot; the returned shard lives at
  /// [shardPath].
  Shard recoverPartialSnapshot({
    required String shardPath,
    required Map<String, dynamic> currentManifest,
    required String snapshotPath,
    required Map<String, dynamic> snapshotManifest,
  }) {
    final b = bindings;
    final a = shardPath.toNativeUtf8();
    final cm = jsonEncode(currentManifest).toNativeUtf8();
    final sp = snapshotPath.toNativeUtf8();
    final sm = jsonEncode(snapshotManifest).toNativeUtf8();
    try {
      final h = b.recoverPartialSnapshot(a, cm, sp, sm);
      if (h == nullptr) _fail(b, 'recoverPartialSnapshot');
      return Shard._(b, h);
    } finally {
      calloc.free(a);
      calloc.free(cm);
      calloc.free(sp);
      calloc.free(sm);
    }
  }

  /// Convenience for the "add text / search text" workflow. Opens (or creates)
  /// a shard wired with a BM25 sparse slot and, if [modelDir] is given, a dense
  /// slot — then [TextIndex] embeds on your behalf. See [TextIndex].
  TextIndex openTextIndex(String path,
      {String? modelDir, int denseSize = 384}) {
    final config = <String, dynamic>{
      'sparse_vectors': {
        'bm25': {'modifier': 'idf'},
      },
      if (modelDir != null)
        'vectors': {
          'dense': {'size': denseSize, 'distance': 'Cosine'},
        },
    };
    final dir = Directory(path);
    final hasData = dir.existsSync() && dir.listSync().isNotEmpty;
    final shard = hasData ? loadShard(path) : createShard(path, config);
    final bm25 = createBm25();
    final dense = modelDir == null ? null : createDense(modelDir);
    return TextIndex._(shard, bm25, dense);
  }
}

/// An open vector shard — the on-device store + index. Operations are
/// synchronous; for large batches run them in an isolate. Unusable after
/// [close].
class Shard {
  Shard._(this._b, this._h);

  final QdrantEdgeBindings _b;
  Pointer<QeShardHandle> _h;
  bool _closed = false;

  void _check() {
    if (_closed) throw QdrantEdgeException('shard is closed');
  }

  void _strOp(
    int Function(Pointer<QeShardHandle>, Pointer<Utf8>) fn,
    String s,
    String op,
  ) {
    _check();
    final p = s.toNativeUtf8();
    try {
      if (fn(_h, p) != 0) _fail(_b, op);
    } finally {
      calloc.free(p);
    }
  }

  dynamic _strJson(
    Pointer<Utf8> Function(Pointer<QeShardHandle>, Pointer<Utf8>) fn,
    String s,
    String op,
  ) {
    _check();
    final p = s.toNativeUtf8();
    try {
      return _takeJson(_b, fn(_h, p), op);
    } finally {
      calloc.free(p);
    }
  }

  /// Upsert points: `[{id, vector, payload?}, ...]`. `vector` is a dense list,
  /// a `{indices, values}` sparse map, or a `{name: vector}` map for named slots.
  void upsert(List<Map<String, dynamic>> points) =>
      _strOp(_b.shardUpsert, jsonEncode(points), 'upsert');

  /// Delete points by id (u64 numbers or UUID strings).
  void deletePoints(List<dynamic> ids) =>
      _strOp(_b.shardDeletePoints, jsonEncode(ids), 'deletePoints');

  /// Nearest-neighbor search. [request] is a `SearchRequest` map
  /// (`{vector, using?, limit, filter?, with_payload?, ...}`). Returns scored
  /// points.
  List<Map<String, dynamic>> search(Map<String, dynamic> request) =>
      (_strJson(_b.shardSearch, jsonEncode(request), 'search') as List)
          .cast<Map<String, dynamic>>();

  /// Full query with prefetches + fusion (hybrid). [request] is a `QueryRequest`
  /// map. Returns scored points.
  List<Map<String, dynamic>> query(Map<String, dynamic> request) =>
      (_strJson(_b.shardQuery, jsonEncode(request), 'query') as List)
          .cast<Map<String, dynamic>>();

  /// Retrieve points by id.
  List<Map<String, dynamic>> retrieve(
    List<dynamic> ids, {
    bool withPayload = true,
    bool withVector = false,
  }) {
    _check();
    final p = jsonEncode(ids).toNativeUtf8();
    try {
      final r = _b.shardRetrieve(_h, p, withPayload, withVector);
      return (_takeJson(_b, r, 'retrieve') as List)
          .cast<Map<String, dynamic>>();
    } finally {
      calloc.free(p);
    }
  }

  /// Paginated scroll. [request] is a `ScrollRequest` map. Returns
  /// `{points, next_offset}`.
  Map<String, dynamic> scroll(Map<String, dynamic> request) =>
      (_strJson(_b.shardScroll, jsonEncode(request), 'scroll') as Map)
          .cast<String, dynamic>();

  /// Count points, optionally with a [filter].
  int count({Map<String, dynamic>? filter}) {
    _check();
    final p = (filter == null ? '' : jsonEncode(filter)).toNativeUtf8();
    try {
      final n = _b.shardCount(_h, p);
      if (n < 0) _fail(_b, 'count');
      return n;
    } finally {
      calloc.free(p);
    }
  }

  /// Shard metadata (`{points_count, segments_count, ...}`).
  Map<String, dynamic> info() {
    _check();
    return (_takeJson(_b, _b.shardInfo(_h), 'info') as Map)
        .cast<String, dynamic>();
  }

  /// Count points per unique value of a payload key. [request] is a
  /// `FacetRequest` map (`{key, limit?, filter?, exact?}`).
  Map<String, dynamic> facet(Map<String, dynamic> request) =>
      (_strJson(_b.shardFacet, jsonEncode(request), 'facet') as Map)
          .cast<String, dynamic>();

  /// Set (merge) payload. [op] is `{payload, points?, filter?, key?}`.
  void setPayload(Map<String, dynamic> op) =>
      _strOp(_b.shardSetPayload, jsonEncode(op), 'setPayload');

  /// Overwrite payload entirely. Same shape as [setPayload].
  void overwritePayload(Map<String, dynamic> op) =>
      _strOp(_b.shardOverwritePayload, jsonEncode(op), 'overwritePayload');

  /// Delete payload keys. [op] is `{keys, points?, filter?}`.
  void deletePayload(Map<String, dynamic> op) =>
      _strOp(_b.shardDeletePayload, jsonEncode(op), 'deletePayload');

  /// Clear all payload from points or by filter. [target] is
  /// `{points: [...]}` or `{filter: ...}`.
  void clearPayload(Map<String, dynamic> target) =>
      _strOp(_b.shardClearPayload, jsonEncode(target), 'clearPayload');

  /// Create a payload field index. [type] is one of `keyword`, `integer`,
  /// `float`, `geo`, `text`, `bool`, `datetime`.
  void createFieldIndex(String field, String type) {
    _check();
    final f = field.toNativeUtf8();
    final t = type.toNativeUtf8();
    try {
      if (_b.shardCreateFieldIndex(_h, f, t) != 0)
        _fail(_b, 'createFieldIndex');
    } finally {
      calloc.free(f);
      calloc.free(t);
    }
  }

  /// Delete a payload field index.
  void deleteFieldIndex(String field) =>
      _strOp(_b.shardDeleteFieldIndex, field, 'deleteFieldIndex');

  /// Add a named vector slot at runtime. [op] is
  /// `{vector_name, config: {dense}|{sparse}}`.
  void createVectorName(Map<String, dynamic> op) =>
      _strOp(_b.shardCreateVectorName, jsonEncode(op), 'createVectorName');

  /// Remove a named vector slot.
  void deleteVectorName(String name) =>
      _strOp(_b.shardDeleteVectorName, name, 'deleteVectorName');

  /// Set the global HNSW config and persist.
  void setHnswConfig(Map<String, dynamic> config) =>
      _strOp(_b.shardSetHnswConfig, jsonEncode(config), 'setHnswConfig');

  /// Set the HNSW config for one named vector (`''` = default) and persist.
  void setVectorHnswConfig(String vectorName, Map<String, dynamic> config) {
    _check();
    final v = vectorName.toNativeUtf8();
    final c = jsonEncode(config).toNativeUtf8();
    try {
      if (_b.shardSetVectorHnswConfig(_h, v, c) != 0) {
        _fail(_b, 'setVectorHnswConfig');
      }
    } finally {
      calloc.free(v);
      calloc.free(c);
    }
  }

  /// Set the optimizers config and persist.
  void setOptimizersConfig(Map<String, dynamic> config) => _strOp(
      _b.shardSetOptimizersConfig, jsonEncode(config), 'setOptimizersConfig');

  /// Read this shard's snapshot manifest (opaque JSON string).
  String snapshotManifest() {
    _check();
    final p = _b.shardSnapshotManifest(_h);
    if (p == nullptr) _fail(_b, 'snapshotManifest');
    try {
      return p.toDartString();
    } finally {
      _b.freeString(p);
    }
  }

  /// Flush pending writes to disk.
  void flush() {
    _check();
    _b.shardFlush(_h);
  }

  /// Run optimizers. Returns 1 if work was done, 0 if already optimal.
  int optimize() {
    _check();
    final r = _b.shardOptimize(_h);
    if (r < 0) _fail(_b, 'optimize');
    return r;
  }

  /// Close the shard (flushes). Idempotent; the instance is unusable afterwards.
  void close() {
    if (_closed) return;
    _b.shardClose(_h);
    _h = nullptr;
    _closed = true;
  }
}

/// On-device BM25 sparse embedder. Reusable across texts and shards.
class Bm25 {
  Bm25._(this._b, this._h);

  final QdrantEdgeBindings _b;
  Pointer<QeBm25Handle> _h;
  bool _closed = false;

  /// Embed a query (each unique token weighted 1.0). Returns `{indices, values}`.
  Map<String, dynamic> embedQuery(String text) =>
      _embed(_b.bm25EmbedQuery, text, 'embedQuery');

  /// Embed a document (BM25 TF weights). Returns `{indices, values}`.
  Map<String, dynamic> embedDocument(String text) =>
      _embed(_b.bm25EmbedDocument, text, 'embedDocument');

  Map<String, dynamic> _embed(
    Pointer<Utf8> Function(Pointer<QeBm25Handle>, Pointer<Utf8>) fn,
    String text,
    String op,
  ) {
    if (_closed) throw QdrantEdgeException('bm25 is closed');
    final t = text.toNativeUtf8();
    try {
      final p = fn(_h, t);
      if (p == nullptr) _fail(_b, op);
      try {
        return (jsonDecode(p.toDartString()) as Map).cast<String, dynamic>();
      } finally {
        _b.freeString(p);
      }
    } finally {
      calloc.free(t);
    }
  }

  /// Free the underlying model.
  void close() {
    if (_closed) return;
    _b.bm25Destroy(_h);
    _h = nullptr;
    _closed = true;
  }
}

/// On-device dense (semantic) embedder. Reusable across texts and shards.
class Dense {
  Dense._(this._b, this._h);

  final QdrantEdgeBindings _b;
  Pointer<QeDenseHandle> _h;
  bool _closed = false;

  /// Embed [text] into an L2-normalized dense vector.
  List<double> embed(String text) {
    if (_closed) throw QdrantEdgeException('dense is closed');
    final t = text.toNativeUtf8();
    try {
      final p = _b.denseEmbed(_h, t);
      if (p == nullptr) _fail(_b, 'embed');
      try {
        return (jsonDecode(p.toDartString()) as List)
            .cast<num>()
            .map((e) => e.toDouble())
            .toList();
      } finally {
        _b.freeString(p);
      }
    } finally {
      calloc.free(t);
    }
  }

  /// Free the underlying model.
  void close() {
    if (_closed) return;
    _b.denseDestroy(_h);
    _h = nullptr;
    _closed = true;
  }
}

/// Convenience wrapper for text-first use: it owns a [Shard] plus a [Bm25]
/// embedder (and an optional [Dense] one) and embeds text for you. Lexical-only
/// by default; pass `modelDir` to [QdrantEdge.openTextIndex] for hybrid.
class TextIndex {
  TextIndex._(this.shard, this._bm25, this._dense);

  /// The underlying shard, for direct access (filters, payload ops, etc.).
  final Shard shard;
  final Bm25 _bm25;
  final Dense? _dense;

  /// True when semantic (dense) search is enabled.
  bool get isHybrid => _dense != null;

  /// Add (upsert) a document. Embeds [text] with BM25 (and dense, if hybrid).
  void add(dynamic id, String text, {Map<String, dynamic>? payload}) {
    final vector = <String, dynamic>{'bm25': _bm25.embedDocument(text)};
    if (_dense != null) vector['dense'] = _dense.embed(text);
    shard.upsert([
      {'id': id, 'vector': vector, if (payload != null) 'payload': payload},
    ]);
  }

  /// Search for [text]. Lexical (BM25) unless hybrid, in which case dense + BM25
  /// are fused with Reciprocal Rank Fusion.
  List<Map<String, dynamic>> search(
    String text, {
    int limit = 10,
    bool withPayload = true,
    Map<String, dynamic>? filter,
  }) {
    final sparse = _bm25.embedQuery(text);
    if (_dense == null) {
      return shard.search({
        'vector': sparse,
        'using': 'bm25',
        'limit': limit,
        'with_payload': withPayload,
        if (filter != null) 'filter': filter,
      });
    }
    final dense = _dense.embed(text);
    return shard.query({
      'prefetch': [
        {'query': dense, 'using': 'dense', 'limit': limit * 5},
        {'query': sparse, 'using': 'bm25', 'limit': limit * 5},
      ],
      'query': {'fusion': 'rrf'},
      'limit': limit,
      'with_payload': withPayload,
      if (filter != null) 'filter': filter,
    });
  }

  /// Number of stored documents.
  int count() => shard.count();

  /// Flush pending writes.
  void flush() => shard.flush();

  /// Close the shard and embedders.
  void close() {
    shard.close();
    _bm25.close();
    _dense?.close();
  }
}
