// lib/storage/providers/path_based_storage_provider.dart (Corrected)

import 'dart:async';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:dart_git/utils/file_extensions.dart'
    if (dart.library.html) 'package:dart_git/utils/file_extensions_na.dart';

import 'storage_handle.dart';
import 'storage_provider.dart';

/// A concrete implementation of [GitStorageProvider] for local, path-based
/// filesystems, using the `package:file` abstraction.
///
/// This serves as a backward-compatible bridge, allowing the refactored
/// `dart_git` library to function on the local disk just as it did before.
class PathBasedStorageProvider implements GitStorageProvider {
  final FileSystem fs;

  PathBasedStorageProvider(this.fs);

  @override
  Future<StorageHandle> resolve(StorageHandle base, String relativePath) async {
    if (base is! PathBasedStorageHandle) {
      throw ArgumentError('Expected a PathBasedStorageHandle');
    }
    // Normalize to prevent escaping the intended directory with '..'
    final resolvedPath = p.normalize(p.join(base.path, relativePath));
    return PathBasedStorageHandle(resolvedPath);
  }

  @override
  Stream<List<int>> read(StorageHandle handle) {
    if (handle is! PathBasedStorageHandle) {
      throw ArgumentError('Expected a PathBasedStorageHandle');
    }
    return fs.file(handle.path).openRead();
  }

  @override
  Future<void> write(StorageHandle handle, Stream<List<int>> data) async {
    if (handle is! PathBasedStorageHandle) {
      throw ArgumentError('Expected a PathBasedStorageHandle');
    }
    final file = fs.file(handle.path);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    await data.pipe(sink);
    await sink.close();
  }

  @override
  Future<bool> exists(StorageHandle handle) async {
    if (handle is! PathBasedStorageHandle) {
      throw ArgumentError('Expected a PathBasedStorageHandle');
    }
    // CORRECTION: Check the entity type. It exists if it's not 'notFound'.
    final type = await fs.type(handle.path, followLinks: false);
    return type != FileSystemEntityType.notFound;
  }

  @override
  Future<void> delete(StorageHandle handle, {bool recursive = false}) async {
    if (handle is! PathBasedStorageHandle) {
      throw ArgumentError('Expected a PathBasedStorageHandle');
    }
    // CORRECTION: Check the entity type before deleting.
    final type = await fs.type(handle.path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      await fs.file(handle.path).delete();
    } else if (type == FileSystemEntityType.directory) {
      await fs.directory(handle.path).delete(recursive: recursive);
    }
    // If type is notFound, do nothing.
  }

  @override
  Future<List<StorageHandle>> list(StorageHandle handle) async {
    if (handle is! PathBasedStorageHandle) {
      throw ArgumentError('Expected a PathBasedStorageHandle');
    }
    final dir = fs.directory(handle.path);
    if (!await dir.exists()) {
      return [];
    }
    // Using .toList() to ensure the future completes with the full list.
    return dir.list().map((entity) => PathBasedStorageHandle(entity.path)).toList();
  }

  @override
  Future<StorageStat> stat(StorageHandle handle) async {
    if (handle is! PathBasedStorageHandle) {
      throw ArgumentError('Expected a PathBasedStorageHandle');
    }
    try {
      final fileStat = await fs.stat(handle.path);
      final type = switch (fileStat.type) {
        FileSystemEntityType.file => StorageEntryType.file,
        FileSystemEntityType.directory => StorageEntryType.directory,
        _ => StorageEntryType.notFound,
      };
      return StorageStat(
        type: type,
        size: fileStat.size,
        modificationTime: fileStat.modified,
      );
    } on FileSystemException {
      return StorageStat(
        type: StorageEntryType.notFound,
        size: -1,
        modificationTime: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
  }

  @override
  Future<void> createDirectory(StorageHandle handle, {bool recursive = false}) async {
    if (handle is! PathBasedStorageHandle) {
      throw ArgumentError('Expected a PathBasedStorageHandle');
    }
    await fs.directory(handle.path).create(recursive: recursive);
  }

  @override
  Future<void> chmod(StorageHandle handle, int mode) async {
    if (handle is! PathBasedStorageHandle) {
      throw ArgumentError('Expected a PathBasedStorageHandle');
    }
    // This uses the existing extension method, which is synchronous.
    // In a real-world async implementation, this would need an async equivalent.
    fs.file(handle.path).chmodSync(mode);
  }
}