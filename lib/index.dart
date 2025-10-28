// lib/index.dart (Corrected)

import 'dart:async';
import 'dart:typed_data'; // Import for Uint8List
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/exceptions.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/index.dart';
import 'package:dart_git/plumbing/objects/blob.dart';
import 'package:dart_git/storage/providers/storage_handle.dart';
import 'package:stdlibc/stdlibc.dart' as stdlibc; // Import for the Stat interface

extension Index on GitRepository {
  /// Adds file contents to the index.
  /// The [pathSpec] is a relative path within the working tree.
  Future<void> add(String pathSpec) async {
    final index = await indexStorage.readIndex();
    final handle = await workTreeFile(pathSpec);

    final stat = await workTreeProvider.stat(handle);
    switch (stat.type) {
      case StorageEntryType.file:
        await _addFileToIndex(index, handle, stat);
        break;
      case StorageEntryType.directory:
        await _addDirectoryToIndex(index, handle, recursive: true);
        break;
      case StorageEntryType.notFound:
        throw GitFileNotFound(pathSpec);
    }

    await indexStorage.writeIndex(index);
  }

  Future<GitIndexEntry> _addFileToIndex(
    GitIndex index,
    StorageHandle handle,
    StorageStat stat,
  ) async {
    final pathSpec = await this.pathSpec(handle);

    // Check if the file is already in the index and unchanged
    final existingEntryIndex = index.entries.indexWhere((e) => e.path == pathSpec);
    if (existingEntryIndex != -1) {
      // FIX: Corrected typo from 'existingEntry-1' to 'existingEntryIndex'
      final entry = index.entries[existingEntryIndex];
      if (entry.mTime.isAtSameMomentAs(stat.modificationTime) &&
          entry.fileSize == stat.size) {
        return entry;
      }
    }

    // Read file contents and create a blob
    final dataStream = workTreeProvider.read(handle);
    final byteList = await dataStream.expand((b) => b).toList();
    // FIX: Explicitly create a Uint8List
    final data = Uint8List.fromList(byteList);
    final blob = GitBlob(data, null); // Hash is computed on creation
    final hash = await objStorage.writeObject(blob);

    // Create a new GitIndexEntry from the abstract stat and hash.
    final syntheticStat = _mapStorageStatToLibcStat(stat);
    // FIX: The adapter now implements stdlibc.Stat, so this assignment is valid.
    final newEntry = GitIndexEntry.fromFS(pathSpec, syntheticStat, hash);

    if (existingEntryIndex != -1) {
      index.entries[existingEntryIndex] = newEntry;
    } else {
      index.entries.add(newEntry);
    }
    return newEntry;
  }

  Future<void> _addDirectoryToIndex(
    GitIndex index,
    StorageHandle dirHandle, {
    bool recursive = false,
  }) async {
    final gitDirRelativePath = await this.pathSpec(gitDir);
    
    final entities = await workTreeProvider.list(dirHandle);
    for (var entityHandle in entities) {
      final entityPathSpec = await this.pathSpec(entityHandle);

      if (entityPathSpec.startsWith(gitDirRelativePath)) {
        continue;
      }
      
      final stat = await workTreeProvider.stat(entityHandle);
      if (stat.type == StorageEntryType.file) {
        await _addFileToIndex(index, entityHandle, stat);
      } else if (recursive && stat.type == StorageEntryType.directory) {
        await _addDirectoryToIndex(index, entityHandle, recursive: true);
      }
    }
  }

  /// Removes files from the index and optionally from the working tree.
  Future<void> rm(String pathSpec, {bool rmFromFs = true}) async {
    final index = await indexStorage.readIndex();
    final handle = await workTreeFile(pathSpec);

    final stat = await workTreeProvider.stat(handle);
    switch (stat.type) {
      case StorageEntryType.file:
        _rmFileFromIndex(index, pathSpec);
        if (rmFromFs) {
          await workTreeProvider.delete(handle);
        }
        break;
      case StorageEntryType.directory:
        await _rmDirectoryFromIndex(index, handle, recursive: true);
        if (rmFromFs) {
          await workTreeProvider.delete(handle, recursive: true);
        }
        break;
      case StorageEntryType.notFound:
        throw GitFileNotFound(pathSpec);
    }

    await indexStorage.writeIndex(index);
  }

  /// Removes a single file path from the index object.
  GitHash _rmFileFromIndex(GitIndex index, String pathSpec) {
    final hash = index.removePath(pathSpec);
    if (hash == null) {
      throw GitFileNotFound(pathSpec);
    }
    return hash;
  }

  Future<void> _rmDirectoryFromIndex(
    GitIndex index,
    StorageHandle dirHandle, {
    bool recursive = false,
  }) async {
    final gitDirRelativePath = await this.pathSpec(gitDir);

    final entities = await workTreeProvider.list(dirHandle);
    for (var entityHandle in entities) {
      final entityPathSpec = await this.pathSpec(entityHandle);
      
      if (entityPathSpec.startsWith(gitDirRelativePath)) {
        continue;
      }

      final stat = await workTreeProvider.stat(entityHandle);
      if (stat.type == StorageEntryType.file) {
        _rmFileFromIndex(index, entityPathSpec);
      } else if (recursive && stat.type == StorageEntryType.directory) {
        await _rmDirectoryFromIndex(index, entityHandle, recursive: true);
      }
    }
    final dirPathSpec = await this.pathSpec(dirHandle);
    index.removePath(dirPathSpec);
  }
}

/// Helper to bridge the abstract [StorageStat] with the concrete [stdlibc.Stat].
stdlibc.Stat _mapStorageStatToLibcStat(StorageStat stat) {
  return _LibcStatAdapter(
    st_mtim: stat.modificationTime,
    st_ctim: stat.modificationTime,
    st_size: stat.size,
    st_dev: 0,
    st_ino: 0,
    st_mode: 0,
    st_uid: 0,
    st_gid: 0,
  );
}

/// An adapter class that implements the [stdlibc.Stat] interface.
/// This allows us to create a `Stat` object from our abstract [StorageStat]
/// without depending on the actual `stdlibc` implementation details.
class _LibcStatAdapter implements stdlibc.Stat {
  @override
  final DateTime st_atim; // Not used by GitIndexEntry, can be default
  @override
  final DateTime st_mtim;
  @override
  final DateTime st_ctim;
  @override
  final int st_size;
  @override
  final int st_dev;
  @override
  final int st_ino;
  @override
  final int st_mode;
  @override
  final int st_uid;
  @override
  final int st_gid;

  // Fields not required by GitIndexEntry, provide defaults.
  @override
  int get st_nlink => 0;
  @override
  int get st_rdev => 0;
  @override
  int get st_blksize => 0;
  @override
  int get st_blocks => 0;

  _LibcStatAdapter({
    required this.st_mtim,
    required this.st_ctim,
    required this.st_size,
    required this.st_dev,
    required this.st_ino,
    required this.st_mode,
    required this.st_uid,
    required this.st_gid,
  }) : st_atim = st_mtim; // Access time can default to modification time
}