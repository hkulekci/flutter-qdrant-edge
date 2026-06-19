/// On-device vector search for Flutter, powered by the `qdrant-edge` Rust crate.
///
/// Text in, search results out — BM25 embedding happens inside Rust, so there
/// is no model download and no network. Everything is local to the device.
///
/// ```dart
/// final db = QdrantEdge.open('${dir.path}/notes');
/// db.add(1, 'the quick brown fox', payload: {'title': 'fox'});
/// db.add(2, 'stock markets rallied', payload: {'title': 'finance'});
/// final hits = db.search('brown fox', limit: 5);
/// db.close();
/// ```
library qdrant_edge_flutter;

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'src/bindings.dart';

/// A single search result.
class QdrantHit {
  QdrantHit({required this.id, required this.score, this.payload});

  /// Point id (stringified — numeric or UUID).
  final String id;

  /// Similarity score (higher is closer).
  final double score;

  /// Stored payload, if any.
  final Map<String, dynamic>? payload;

  factory QdrantHit.fromJson(Map<String, dynamic> json) => QdrantHit(
        id: json['id'] as String,
        score: (json['score'] as num).toDouble(),
        payload: (json['payload'] as Map?)?.cast<String, dynamic>(),
      );

  @override
  String toString() => 'QdrantHit(id: $id, score: $score, payload: $payload)';
}

/// Thrown when a native call fails. The message comes from Rust.
class QdrantEdgeException implements Exception {
  QdrantEdgeException(this.message);
  final String message;
  @override
  String toString() => 'QdrantEdgeException: $message';
}

/// A handle to an on-device vector database.
///
/// Not safe to use after [close]. Operations are synchronous; for large
/// batches consider running them in an isolate.
class QdrantEdge {
  QdrantEdge._(this._bindings, this._handle);

  static QdrantEdgeBindings? _cachedBindings;

  final QdrantEdgeBindings _bindings;
  Pointer<QeHandle> _handle;
  bool _closed = false;

  static QdrantEdgeBindings get _resolved =>
      _cachedBindings ??= QdrantEdgeBindings(QdrantEdgeBindings.loadLibrary());

  /// Open (or create) a database at [path]. The directory is created if needed.
  ///
  /// If [modelDir] points to a directory with a neural model (config.json,
  /// tokenizer.json, model.safetensors), hybrid semantic search is enabled;
  /// otherwise search is lexical (BM25) only.
  factory QdrantEdge.open(String path, {String? modelDir}) {
    final bindings = _resolved;
    final pathC = path.toNativeUtf8();
    final modelC = (modelDir ?? '').toNativeUtf8();
    try {
      final handle = bindings.open(pathC, modelC);
      if (handle == nullptr) {
        throw QdrantEdgeException(_takeLastError(bindings) ?? 'open failed');
      }
      return QdrantEdge._(bindings, handle);
    } finally {
      calloc.free(pathC);
      calloc.free(modelC);
    }
  }

  /// Add (upsert) a document. [id] is a numeric point id; re-adding the same
  /// id overwrites. [payload] is any JSON-serializable map.
  void add(int id, String text, {Map<String, dynamic>? payload}) {
    _ensureOpen();
    final textC = text.toNativeUtf8();
    final payloadC =
        (payload == null ? '' : jsonEncode(payload)).toNativeUtf8();
    try {
      final rc = _bindings.add(_handle, id, textC, payloadC);
      if (rc != 0) {
        throw QdrantEdgeException(_takeLastError(_bindings) ?? 'add failed');
      }
    } finally {
      calloc.free(textC);
      calloc.free(payloadC);
    }
  }

  /// Search for the [limit] documents most similar to [query].
  List<QdrantHit> search(String query, {int limit = 10}) {
    _ensureOpen();
    final queryC = query.toNativeUtf8();
    try {
      final resultC = _bindings.search(_handle, queryC, limit);
      if (resultC == nullptr) {
        throw QdrantEdgeException(_takeLastError(_bindings) ?? 'search failed');
      }
      try {
        final jsonStr = resultC.toDartString();
        final list = jsonDecode(jsonStr) as List<dynamic>;
        return list
            .map((e) => QdrantHit.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      } finally {
        _bindings.stringFree(resultC);
      }
    } finally {
      calloc.free(queryC);
    }
  }

  /// Delete a point by numeric [id].
  void delete(int id) {
    _ensureOpen();
    final rc = _bindings.delete(_handle, id);
    if (rc != 0) {
      throw QdrantEdgeException(_takeLastError(_bindings) ?? 'delete failed');
    }
  }

  /// Delete every point matching a Qdrant [filter] (e.g. a payload match).
  /// Example: `{'must': [{'key': 'docId', 'match': {'value': 7}}]}`.
  void deleteByFilter(Map<String, dynamic> filter) {
    _ensureOpen();
    final filterC = jsonEncode(filter).toNativeUtf8();
    try {
      final rc = _bindings.deleteByFilter(_handle, filterC);
      if (rc != 0) {
        throw QdrantEdgeException(
            _takeLastError(_bindings) ?? 'deleteByFilter failed');
      }
    } finally {
      calloc.free(filterC);
    }
  }

  /// Number of stored points.
  int count() {
    _ensureOpen();
    final n = _bindings.count(_handle);
    if (n < 0) {
      throw QdrantEdgeException(_takeLastError(_bindings) ?? 'count failed');
    }
    return n;
  }

  /// Flush pending writes to disk.
  void flush() {
    _ensureOpen();
    final rc = _bindings.flush(_handle);
    if (rc != 0) {
      throw QdrantEdgeException(_takeLastError(_bindings) ?? 'flush failed');
    }
  }

  /// Close the database. Idempotent; the instance is unusable afterwards.
  void close() {
    if (_closed) return;
    _bindings.close(_handle);
    _handle = nullptr;
    _closed = true;
  }

  void _ensureOpen() {
    if (_closed) {
      throw QdrantEdgeException('database is closed');
    }
  }

  static String? _takeLastError(QdrantEdgeBindings bindings) {
    final errC = bindings.lastError();
    if (errC == nullptr) return null;
    try {
      return errC.toDartString();
    } finally {
      bindings.stringFree(errC);
    }
  }
}
