// Raw `dart:ffi` bindings to the qdrant_edge_flutter C ABI.
//
// Hand-written to match rust/include/qdrant_edge_flutter.h. The high-level,
// ergonomic API lives in ../qdrant_edge_flutter.dart — prefer that.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Opaque database handle (matches `struct QeHandle`).
final class QeHandle extends Opaque {}

// ---- C function typedefs --------------------------------------------------

typedef _QeOpenC = Pointer<QeHandle> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _QeOpenDart = Pointer<QeHandle> Function(Pointer<Utf8>, Pointer<Utf8>);

typedef _QeAddC = Int32 Function(
    Pointer<QeHandle>, Uint64, Pointer<Utf8>, Pointer<Utf8>);
typedef _QeAddDart = int Function(
    Pointer<QeHandle>, int, Pointer<Utf8>, Pointer<Utf8>);

typedef _QeSearchC = Pointer<Utf8> Function(
    Pointer<QeHandle>, Pointer<Utf8>, Uint32);
typedef _QeSearchDart = Pointer<Utf8> Function(
    Pointer<QeHandle>, Pointer<Utf8>, int);

typedef _QeDeleteC = Int32 Function(Pointer<QeHandle>, Uint64);
typedef _QeDeleteDart = int Function(Pointer<QeHandle>, int);

typedef _QeDeleteByFilterC = Int32 Function(Pointer<QeHandle>, Pointer<Utf8>);
typedef _QeDeleteByFilterDart = int Function(Pointer<QeHandle>, Pointer<Utf8>);

typedef _QeCountC = Int64 Function(Pointer<QeHandle>);
typedef _QeCountDart = int Function(Pointer<QeHandle>);

typedef _QeFlushC = Int32 Function(Pointer<QeHandle>);
typedef _QeFlushDart = int Function(Pointer<QeHandle>);

typedef _QeCloseC = Void Function(Pointer<QeHandle>);
typedef _QeCloseDart = void Function(Pointer<QeHandle>);

typedef _QeLastErrorC = Pointer<Utf8> Function();
typedef _QeLastErrorDart = Pointer<Utf8> Function();

typedef _QeStringFreeC = Void Function(Pointer<Utf8>);
typedef _QeStringFreeDart = void Function(Pointer<Utf8>);

/// Thin wrapper resolving and exposing the native symbols.
class QdrantEdgeBindings {
  QdrantEdgeBindings(DynamicLibrary lib)
      : open = lib.lookupFunction<_QeOpenC, _QeOpenDart>('qe_open'),
        add = lib.lookupFunction<_QeAddC, _QeAddDart>('qe_add'),
        search = lib.lookupFunction<_QeSearchC, _QeSearchDart>('qe_search'),
        delete = lib.lookupFunction<_QeDeleteC, _QeDeleteDart>('qe_delete'),
        deleteByFilter =
            lib.lookupFunction<_QeDeleteByFilterC, _QeDeleteByFilterDart>(
                'qe_delete_by_filter'),
        count = lib.lookupFunction<_QeCountC, _QeCountDart>('qe_count'),
        flush = lib.lookupFunction<_QeFlushC, _QeFlushDart>('qe_flush'),
        close = lib.lookupFunction<_QeCloseC, _QeCloseDart>('qe_close'),
        lastError = lib
            .lookupFunction<_QeLastErrorC, _QeLastErrorDart>('qe_last_error'),
        stringFree = lib.lookupFunction<_QeStringFreeC, _QeStringFreeDart>(
            'qe_string_free');

  final _QeOpenDart open;
  final _QeAddDart add;
  final _QeSearchDart search;
  final _QeDeleteDart delete;
  final _QeDeleteByFilterDart deleteByFilter;
  final _QeCountDart count;
  final _QeFlushDart flush;
  final _QeCloseDart close;
  final _QeLastErrorDart lastError;
  final _QeStringFreeDart stringFree;

  /// Load the native library for the current platform.
  ///
  /// Android links a shared object; iOS/macOS link the static lib into the
  /// app binary, so symbols are resolved from the running process.
  static DynamicLibrary loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libqdrant_edge_flutter.so');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('libqdrant_edge_flutter.so');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('qdrant_edge_flutter.dll');
    }
    throw UnsupportedError('Unsupported platform for qdrant_edge_flutter');
  }
}
