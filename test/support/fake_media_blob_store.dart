import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:menstrul_track/services/media_blob_store.dart';

/// An in-memory [MediaBlobStore] with fault injection.
///
/// This repo normally defines test helpers inline per file. This one is shared
/// because several suites (upload, sync, orphan sweep, the timeline) need the
/// SAME two failure shapes, and both are easy to get subtly wrong:
///
/// - [completeUploadThenFail] reproduces the orphan: the object really lands in
///   the bucket and the caller still sees an error. That is the window between
///   "bytes uploaded" and "Firestore document written", and the residue is an
///   unreferenced object nothing lists and nothing would ever delete.
/// - [gate] holds an upload mid-flight so a test can sign out underneath it and
///   prove the completion cannot write under the new account's uid.
class FakeMediaBlobStore implements MediaBlobStore {
  /// path → byte length of every object currently "in the bucket".
  final Map<String, int> objects = {};

  /// Every path passed to [delete], in order.
  final List<String> deleted = [];

  /// Every path uploaded, in order — lets a test assert thumb-before-original.
  final List<String> uploads = [];

  /// Paths containing this substring throw instead of completing.
  String? failOn;

  /// When true, uploads store the object and THEN throw.
  bool completeUploadThenFail = false;

  /// When set, uploads await it before completing.
  Completer<void>? gate;

  /// How many uploads are currently parked on [gate].
  ///
  /// Lets a test wait until an upload is genuinely mid-flight before acting on
  /// it. Without this the only observable is [uploads], which is not appended
  /// until AFTER the gate releases — so a test would be racing the very thing
  /// it is trying to hold still.
  int inFlight = 0;

  void _maybeFail(String path) {
    final needle = failOn;
    if (needle != null && path.contains(needle)) {
      throw StateError('injected failure for $path');
    }
  }

  Future<void> _store(String path, int bytes) async {
    _maybeFail(path);
    final g = gate;
    if (g != null) {
      inFlight++;
      try {
        await g.future;
      } finally {
        inFlight--;
      }
    }
    objects[path] = bytes;
    uploads.add(path);
    if (completeUploadThenFail) {
      throw StateError('injected post-upload failure for $path');
    }
  }

  @override
  Future<void> putBytes(String path, Uint8List bytes, String contentType) =>
      _store(path, bytes.length);

  @override
  Future<void> putFile(String path, File file, String contentType) async =>
      _store(path, await file.length());

  @override
  Future<Uint8List> getBytes(String path, {required int maxBytes}) async {
    _maybeFail(path);
    final len = objects[path];
    if (len == null) throw StateError('No bytes at $path');
    if (len > maxBytes) throw StateError('$path exceeds maxBytes');
    return Uint8List.fromList(List.filled(len, 1));
  }

  @override
  Future<void> downloadToFile(String path, File dest) async {
    _maybeFail(path);
    final len = objects[path];
    if (len == null) throw StateError('No bytes at $path');
    await dest.writeAsBytes(List.filled(len, 1), flush: true);
  }

  @override
  Future<void> delete(String path) async {
    _maybeFail(path);
    deleted.add(path);
    objects.remove(path);
  }

  @override
  Future<List<String>> listItemIds(String prefix) async {
    _maybeFail(prefix);
    final root = prefix.endsWith('/') ? prefix : '$prefix/';
    return objects.keys
        .where((k) => k.startsWith(root))
        .map((k) => k.substring(root.length).split('/').first)
        .toSet()
        .toList()
      ..sort();
  }

  @override
  Future<List<String>> listObjectPaths(String prefix) async {
    _maybeFail(prefix);
    final root = prefix.endsWith('/') ? prefix : '$prefix/';
    return objects.keys
        .where((k) => k.startsWith(root) && !k.substring(root.length).contains('/'))
        .toList()
      ..sort();
  }
}
