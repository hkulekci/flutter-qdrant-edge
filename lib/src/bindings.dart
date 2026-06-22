// Raw `dart:ffi` bindings to the qdrant_edge_flutter C ABI.
//
// Hand-written to match rust/include/qdrant_edge_flutter.h. Complex arguments
// and results cross the boundary as JSON strings. The high-level, ergonomic API
// lives in ../qdrant_edge_flutter.dart — prefer that.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Opaque handle to an `EdgeShard` (`struct QeShardHandle`).
final class QeShardHandle extends Opaque {}

/// Opaque handle to a BM25 model (`struct QeBm25Handle`).
final class QeBm25Handle extends Opaque {}

/// Opaque handle to a dense embedder (`struct QeDenseHandle`).
final class QeDenseHandle extends Opaque {}

// ---- C function typedefs --------------------------------------------------

// shard lifecycle
typedef _ShardCreateC = Pointer<QeShardHandle> Function(
    Pointer<Utf8>, Pointer<Utf8>);
typedef _ShardCreateDart = Pointer<QeShardHandle> Function(
    Pointer<Utf8>, Pointer<Utf8>);

typedef _RecoverC = Pointer<QeShardHandle> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _RecoverDart = Pointer<QeShardHandle> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef _ShardVoidC = Void Function(Pointer<QeShardHandle>);
typedef _ShardVoidDart = void Function(Pointer<QeShardHandle>);

typedef _ShardIntC = Int32 Function(Pointer<QeShardHandle>);
typedef _ShardIntDart = int Function(Pointer<QeShardHandle>);

// shard ops taking one JSON string -> int
typedef _ShardStrIntC = Int32 Function(Pointer<QeShardHandle>, Pointer<Utf8>);
typedef _ShardStrIntDart = int Function(Pointer<QeShardHandle>, Pointer<Utf8>);

// shard ops taking two strings -> int
typedef _ShardStr2IntC = Int32 Function(
    Pointer<QeShardHandle>, Pointer<Utf8>, Pointer<Utf8>);
typedef _ShardStr2IntDart = int Function(
    Pointer<QeShardHandle>, Pointer<Utf8>, Pointer<Utf8>);

// shard count -> i64
typedef _ShardCountC = Int64 Function(Pointer<QeShardHandle>, Pointer<Utf8>);
typedef _ShardCountDart = int Function(Pointer<QeShardHandle>, Pointer<Utf8>);

// shard -> JSON string
typedef _ShardJsonC = Pointer<Utf8> Function(Pointer<QeShardHandle>);
typedef _ShardJsonDart = Pointer<Utf8> Function(Pointer<QeShardHandle>);

// shard, JSON string -> JSON string
typedef _ShardStrJsonC = Pointer<Utf8> Function(
    Pointer<QeShardHandle>, Pointer<Utf8>);
typedef _ShardStrJsonDart = Pointer<Utf8> Function(
    Pointer<QeShardHandle>, Pointer<Utf8>);

// retrieve: shard, ids, with_payload, with_vector -> JSON
typedef _RetrieveC = Pointer<Utf8> Function(
    Pointer<QeShardHandle>, Pointer<Utf8>, Bool, Bool);
typedef _RetrieveDart = Pointer<Utf8> Function(
    Pointer<QeShardHandle>, Pointer<Utf8>, bool, bool);

// unpack snapshot: two strings -> int
typedef _Str2IntC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _Str2IntDart = int Function(Pointer<Utf8>, Pointer<Utf8>);

// bm25
typedef _Bm25CreateC = Pointer<QeBm25Handle> Function(Pointer<Utf8>);
typedef _Bm25CreateDart = Pointer<QeBm25Handle> Function(Pointer<Utf8>);
typedef _Bm25VoidC = Void Function(Pointer<QeBm25Handle>);
typedef _Bm25VoidDart = void Function(Pointer<QeBm25Handle>);
typedef _Bm25EmbedC = Pointer<Utf8> Function(
    Pointer<QeBm25Handle>, Pointer<Utf8>);
typedef _Bm25EmbedDart = Pointer<Utf8> Function(
    Pointer<QeBm25Handle>, Pointer<Utf8>);

// dense
typedef _DenseCreateC = Pointer<QeDenseHandle> Function(Pointer<Utf8>);
typedef _DenseCreateDart = Pointer<QeDenseHandle> Function(Pointer<Utf8>);
typedef _DenseVoidC = Void Function(Pointer<QeDenseHandle>);
typedef _DenseVoidDart = void Function(Pointer<QeDenseHandle>);
typedef _DenseEmbedC = Pointer<Utf8> Function(
    Pointer<QeDenseHandle>, Pointer<Utf8>);
typedef _DenseEmbedDart = Pointer<Utf8> Function(
    Pointer<QeDenseHandle>, Pointer<Utf8>);

// error + strings
typedef _LastErrorC = Pointer<Utf8> Function();
typedef _LastErrorDart = Pointer<Utf8> Function();
typedef _FreeStringC = Void Function(Pointer<Utf8>);
typedef _FreeStringDart = void Function(Pointer<Utf8>);

/// Thin wrapper resolving and exposing the native symbols.
class QdrantEdgeBindings {
  QdrantEdgeBindings(DynamicLibrary lib)
      : shardCreate = lib
            .lookupFunction<_ShardCreateC, _ShardCreateDart>('qe_shard_create'),
        shardLoad = lib
            .lookupFunction<_ShardCreateC, _ShardCreateDart>('qe_shard_load'),
        recoverPartialSnapshot = lib.lookupFunction<_RecoverC, _RecoverDart>(
            'qe_recover_partial_snapshot'),
        shardClose =
            lib.lookupFunction<_ShardVoidC, _ShardVoidDart>('qe_shard_close'),
        shardFlush =
            lib.lookupFunction<_ShardVoidC, _ShardVoidDart>('qe_shard_flush'),
        shardOptimize =
            lib.lookupFunction<_ShardIntC, _ShardIntDart>('qe_shard_optimize'),
        shardUpsert = lib
            .lookupFunction<_ShardStrIntC, _ShardStrIntDart>('qe_shard_upsert'),
        shardDeletePoints = lib.lookupFunction<_ShardStrIntC, _ShardStrIntDart>(
            'qe_shard_delete_points'),
        shardSetPayload = lib.lookupFunction<_ShardStrIntC, _ShardStrIntDart>(
            'qe_shard_set_payload'),
        shardOverwritePayload =
            lib.lookupFunction<_ShardStrIntC, _ShardStrIntDart>(
                'qe_shard_overwrite_payload'),
        shardDeletePayload =
            lib.lookupFunction<_ShardStrIntC, _ShardStrIntDart>(
                'qe_shard_delete_payload'),
        shardClearPayload = lib.lookupFunction<_ShardStrIntC, _ShardStrIntDart>(
            'qe_shard_clear_payload'),
        shardCreateVectorName =
            lib.lookupFunction<_ShardStrIntC, _ShardStrIntDart>(
                'qe_shard_create_vector_name'),
        shardDeleteVectorName =
            lib.lookupFunction<_ShardStrIntC, _ShardStrIntDart>(
                'qe_shard_delete_vector_name'),
        shardSetHnswConfig =
            lib.lookupFunction<_ShardStrIntC, _ShardStrIntDart>(
                'qe_shard_set_hnsw_config'),
        shardSetOptimizersConfig =
            lib.lookupFunction<_ShardStrIntC, _ShardStrIntDart>(
                'qe_shard_set_optimizers_config'),
        shardDeleteFieldIndex =
            lib.lookupFunction<_ShardStrIntC, _ShardStrIntDart>(
                'qe_shard_delete_field_index'),
        shardSetVectorHnswConfig =
            lib.lookupFunction<_ShardStr2IntC, _ShardStr2IntDart>(
                'qe_shard_set_vector_hnsw_config'),
        shardCreateFieldIndex =
            lib.lookupFunction<_ShardStr2IntC, _ShardStr2IntDart>(
                'qe_shard_create_field_index'),
        shardCount =
            lib.lookupFunction<_ShardCountC, _ShardCountDart>('qe_shard_count'),
        shardInfo =
            lib.lookupFunction<_ShardJsonC, _ShardJsonDart>('qe_shard_info'),
        shardSnapshotManifest = lib.lookupFunction<_ShardJsonC, _ShardJsonDart>(
            'qe_shard_snapshot_manifest'),
        shardSearch = lib.lookupFunction<_ShardStrJsonC, _ShardStrJsonDart>(
            'qe_shard_search'),
        shardQuery = lib.lookupFunction<_ShardStrJsonC, _ShardStrJsonDart>(
            'qe_shard_query'),
        shardScroll = lib.lookupFunction<_ShardStrJsonC, _ShardStrJsonDart>(
            'qe_shard_scroll'),
        shardFacet = lib.lookupFunction<_ShardStrJsonC, _ShardStrJsonDart>(
            'qe_shard_facet'),
        shardRetrieve =
            lib.lookupFunction<_RetrieveC, _RetrieveDart>('qe_shard_retrieve'),
        unpackSnapshot =
            lib.lookupFunction<_Str2IntC, _Str2IntDart>('qe_unpack_snapshot'),
        bm25Create =
            lib.lookupFunction<_Bm25CreateC, _Bm25CreateDart>('qe_bm25_create'),
        bm25Destroy =
            lib.lookupFunction<_Bm25VoidC, _Bm25VoidDart>('qe_bm25_destroy'),
        bm25EmbedQuery = lib
            .lookupFunction<_Bm25EmbedC, _Bm25EmbedDart>('qe_bm25_embed_query'),
        bm25EmbedDocument = lib.lookupFunction<_Bm25EmbedC, _Bm25EmbedDart>(
            'qe_bm25_embed_document'),
        denseCreate = lib
            .lookupFunction<_DenseCreateC, _DenseCreateDart>('qe_dense_create'),
        denseDestroy =
            lib.lookupFunction<_DenseVoidC, _DenseVoidDart>('qe_dense_destroy'),
        denseEmbed =
            lib.lookupFunction<_DenseEmbedC, _DenseEmbedDart>('qe_dense_embed'),
        lastError =
            lib.lookupFunction<_LastErrorC, _LastErrorDart>('qe_last_error'),
        freeString =
            lib.lookupFunction<_FreeStringC, _FreeStringDart>('qe_free_string');

  final _ShardCreateDart shardCreate;
  final _ShardCreateDart shardLoad;
  final _RecoverDart recoverPartialSnapshot;
  final _ShardVoidDart shardClose;
  final _ShardVoidDart shardFlush;
  final _ShardIntDart shardOptimize;
  final _ShardStrIntDart shardUpsert;
  final _ShardStrIntDart shardDeletePoints;
  final _ShardStrIntDart shardSetPayload;
  final _ShardStrIntDart shardOverwritePayload;
  final _ShardStrIntDart shardDeletePayload;
  final _ShardStrIntDart shardClearPayload;
  final _ShardStrIntDart shardCreateVectorName;
  final _ShardStrIntDart shardDeleteVectorName;
  final _ShardStrIntDart shardSetHnswConfig;
  final _ShardStrIntDart shardSetOptimizersConfig;
  final _ShardStrIntDart shardDeleteFieldIndex;
  final _ShardStr2IntDart shardSetVectorHnswConfig;
  final _ShardStr2IntDart shardCreateFieldIndex;
  final _ShardCountDart shardCount;
  final _ShardJsonDart shardInfo;
  final _ShardJsonDart shardSnapshotManifest;
  final _ShardStrJsonDart shardSearch;
  final _ShardStrJsonDart shardQuery;
  final _ShardStrJsonDart shardScroll;
  final _ShardStrJsonDart shardFacet;
  final _RetrieveDart shardRetrieve;
  final _Str2IntDart unpackSnapshot;
  final _Bm25CreateDart bm25Create;
  final _Bm25VoidDart bm25Destroy;
  final _Bm25EmbedDart bm25EmbedQuery;
  final _Bm25EmbedDart bm25EmbedDocument;
  final _DenseCreateDart denseCreate;
  final _DenseVoidDart denseDestroy;
  final _DenseEmbedDart denseEmbed;
  final _LastErrorDart lastError;
  final _FreeStringDart freeString;

  /// Load the native library for the current platform.
  ///
  /// Android links a shared object; iOS/macOS link the engine as a framework /
  /// static lib into the app binary, so symbols resolve from the process.
  static DynamicLibrary loadLibrary() {
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libqdrant_edge_flutter.so');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('qdrant_edge_flutter.dll');
    }
    throw UnsupportedError('Unsupported platform for qdrant_edge_flutter');
  }
}
