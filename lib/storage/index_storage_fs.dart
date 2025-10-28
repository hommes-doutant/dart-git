// lib/storage/index_storage_fs.dart

import 'dart:async';
import 'dart:typed_data';

import 'package:dart_git/plumbing/index.dart';
import 'package:dart_git/storage/providers/storage_handle.dart';
import 'package:dart_git/storage/providers/storage_provider.dart';

import 'interfaces.dart';

class IndexStorageFS implements IndexStorage {
  final GitStorageProvider _provider;
  final StorageHandle _gitDirHandle;

  // Lazily resolve the handle to the index file.
  late final Future<StorageHandle> _indexHandleFuture =
      _provider.resolve(_gitDirHandle, 'index');

  IndexStorageFS(this._provider, this._gitDirHandle);

  @override
  Future<GitIndex> readIndex() async {
    final indexHandle = await _indexHandleFuture;
    if (!await _provider.exists(indexHandle)) {
      return GitIndex(versionNo: 2);
    }

    final bytesList = await _provider.read(indexHandle).expand((b) => b).toList();
    final bytes = Uint8List.fromList(bytesList);
    return GitIndex.decode(bytes);
  }

  @override
  Future<void> writeIndex(GitIndex index) async {
    final indexHandle = await _indexHandleFuture;
    final data = index.serialize();

    // A common pattern for atomic writes is to write to a temporary file
    // and then rename it. This requires adding 'rename' to the provider.
    // For simplicity here, we write directly.
    await _provider.write(indexHandle, Stream.value(data));
  }

  @override
  Future<void> close() async {
    // No-op for this implementation.
  }
}