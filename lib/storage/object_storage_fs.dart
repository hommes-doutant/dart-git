// lib/storage/object_storage_fs.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:typed_data';

import 'package:charcode/charcode.dart';
import 'package:dart_git/exceptions.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/idx_file.dart';
import 'package:dart_git/plumbing/objects/object.dart';
import 'package:dart_git/plumbing/pack_file.dart';
import 'package:dart_git/storage/providers/storage_handle.dart';
import 'package:dart_git/storage/providers/storage_provider.dart';
import 'package:dart_git/utils/uint8list.dart';

import 'interfaces.dart';

/// An implementation of [ObjectStorage] that uses a [GitStorageProvider] to
/// interact with a filesystem-like backend.
///
/// It supports reading and writing both "loose" and "packed" Git objects.
class ObjectStorageFS implements ObjectStorage {
  final GitStorageProvider _provider;
  final StorageHandle _gitDirHandle;

  // Caching mechanism to avoid re-scanning the packfile directory on every read.
  DateTime? _packDirLastModified;
  var _packFiles = <PackFile>[];

  ObjectStorageFS(this._provider, this._gitDirHandle);

  /// Reads a Git object from storage by its hash.
  ///
  /// It first attempts to find a "loose" object. If not found, it checks all
  /// loaded packfiles for the object. Throws [GitObjectNotFound] if the object
  /// cannot be found in either location.
  @override
  Future<GitObject> read(GitHash hash) async {
    final sha = hash.toString();
    final objectPath = 'objects/${sha.substring(0, 2)}/${sha.substring(2)}';
    final objectHandle = await _provider.resolve(_gitDirHandle, objectPath);

    // 1. Attempt to read as a loose object first.
    if (await _provider.exists(objectHandle)) {
      return readObjectFromHandle(objectHandle, hash);
    }

    // 2. If not found, check the packfiles.
    await _loadPackFilesIfNeeded();
    for (var packFile in _packFiles) {
      final obj = await packFile.object(hash);
      if (obj != null) {
        return obj;
      }
    }

    // 3. If still not found, throw an exception.
    throw GitObjectNotFound(hash);
  }

  /// Writes a Git object to storage as a "loose" object.
  ///
  /// The object is compressed with zlib and stored in a file path derived
  /// from its hash. If an object with the same hash already exists, the write
  /// is skipped.
  @override
  Future<GitHash> writeObject(GitObject obj) async {
    final resultBytes =
        GitObject.envelope(data: obj.serializeData(), format: obj.format());
    final hash = obj.hash;
    final sha = hash.toString();

    final objectPath = 'objects/${sha.substring(0, 2)}/${sha.substring(2)}';
    final objectHandle = await _provider.resolve(_gitDirHandle, objectPath);

    if (await _provider.exists(objectHandle)) {
      return hash; // Object already exists, no need to write.
    }

    final compressed = zlib.encode(resultBytes);
    await _provider.write(objectHandle, Stream.value(compressed));

    return hash;
  }

  /// Scans the `objects/pack` directory for new or modified packfiles.
  ///
  /// This method is optimized to only re-scan if the pack directory's
  /// modification timestamp has changed since the last scan.
  Future<void> _loadPackFilesIfNeeded() async {
    final packDirHandle = await _provider.resolve(_gitDirHandle, 'objects/pack');
    if (!await _provider.exists(packDirHandle)) {
      _packFiles = [];
      return;
    }

    final stat = await _provider.stat(packDirHandle);
    if (stat.modificationTime == _packDirLastModified) {
      return; // Pack directory hasn't changed, no need to reload.
    }
    _packDirLastModified = stat.modificationTime;

    final fileHandles = await _provider.list(packDirHandle);
    final idxHandles = fileHandles.where((h) => h.name.endsWith('.idx'));

    final packFileFutures = idxHandles.map((idxHandle) async {
      try {
        final idxBytes = await _provider.read(idxHandle).expand((b) => b).toList();
        final idxFile = IdxFile.decode(Uint8List.fromList(idxBytes));

        final packFileName = idxHandle.name.replaceAll('.idx', '.pack');
        final packFileHandle = await _provider.resolve(packDirHandle, packFileName);

        if (!await _provider.exists(packFileHandle)) {
          print('Warning: Found index file but missing packfile: ${packFileHandle.uri}');
          return null;
        }

        return await PackFile.fromStorage(
          idx: idxFile,
          provider: _provider,
          handle: packFileHandle,
        );
      } catch (e, st) {
        // Log the error and skip this packfile. This prevents a single
        // corrupted file from crashing the entire operation.
        print('Warning: Failed to load packfile for ${idxHandle.name}. Error: $e\n$st');
        return null;
      }
    }).toList();

    final results = await Future.wait(packFileFutures);
    _packFiles = results.whereType<PackFile>().toList();
  }

  /// Helper to read, decompress, and parse a loose object from a storage handle.
  Future<GitObject> readObjectFromHandle(StorageHandle handle, GitHash hash) async {
    final compressedBytes = await _provider.read(handle).expand((b) => b).toList();
    final raw = zlib.decode(compressedBytes) as Uint8List;

    final spaceIndex = raw.indexOf($space);
    if (spaceIndex == -1) throw GitObjectCorruptedMissingType();

    final nullIndex = raw.indexOf(0x0, spaceIndex);
    if (nullIndex == -1) throw GitObjectCorruptedMissingSize();
    
    final sizeStr = ascii.decode(raw.sublistView(spaceIndex + 1, nullIndex));
    final size = int.tryParse(sizeStr);
    if (size == null) throw GitObjectCorruptedInvalidIntSize();

    final rawData = raw.sublistView(nullIndex + 1);
    if (size != rawData.length) throw GitObjectCorruptedBadSize();

    final fmtStr = ascii.decode(raw.sublistView(0, spaceIndex));
    return createObject(ObjectTypes.getType(fmtStr), rawData, hash);
  }

  @override
  Future<void> close() async {
    // This implementation holds no persistent resources (like file handles),
    // so there's nothing to close. The provider is responsible for managing
    // its own resources.
  }
}