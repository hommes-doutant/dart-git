// lib/index.dart (Refactored for Installment 3)

import 'dart:async';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/exceptions.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/index.dart';
import 'package:dart_git/plumbing/objects/blob.dart';
import 'package:dart_git/storage/providers/storage_handle.dart';
// Note: We are no longer using 'package:stdlibc' directly here.
// Instead, we rely on the StorageStat object from the provider.

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
      final entry = index.entries[existingEntry-1];
      // Compare metadata to see if we can skip reading and hashing the file.
      // NOTE: This comparison is simplified. Git's logic is more complex,
      // involving device and inode numbers which we don't have in our abstract stat.
      // Modification time is a reasonable heuristic.
      if (entry.mTime.isAtSameMomentAs(stat.modificationTime) &&
          entry.fileSize == stat.size) {
        return entry;
      }
    }

    // Read file contents and create a blob
    final dataStream = workTreeProvider.read(handle);
    final data = await dataStream.expand((b) => b).toList();
    final blob = GitBlob(data, null); // Hash is computed on creation
    final hash = await objStorage.writeObject(blob);

    // Create a new GitIndexEntry from the abstract stat and hash.
    // We create a synthetic stdlibc.Stat for compatibility with the existing
    // GitIndexEntry.fromFS constructor. A future refactor could change
    // GitIndexEntry to accept StorageStat directly.
    final syntheticStat = _mapStorageStatToLibcStat(stat);
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

      // Don't add the .git directory itself
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
      throw GitFileNotFound(pathSpec); // Or a different exception might be better
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
    // Also remove the directory entry itself if it exists (though it usually doesn't)
    final dirPathSpec = await this.pathSpec(dirHandle);
    index.removePath(dirPathSpec);
  }
}

// Helper function to bridge the old GitIndexEntry constructor with our new
// abstract StorageStat. This avoids needing to refactor GitIndexEntry itself
// in this installment.
// In a real-world scenario, you might add a new constructor to GitIndexEntry.
_LibcStatAdapter _mapStorageStatToLibcStat(StorageStat stat) {
  return _LibcStatAdapter(
    st_mtim: stat.modificationTime,
    st_ctim: stat.modificationTime, // Using mtime for ctime as a reasonable default
    st_size: stat.size,
    // These values are not available in our abstract provider, so we use defaults.
    // Git on some filesystems uses these to further optimize change detection.
    // The fallback is to rely on mtime and size, which is what we're doing.
    st_dev: 0,
    st_ino: 0,
    st_mode: 0, // Mode is handled separately in GitIndexEntry
    st_uid: 0,
    st_gid: 0,
  );
}

// An adapter class implementing the necessary fields from stdlibc.Stat.
class _LibcStatAdapter {
  final DateTime st_mtim;
  final DateTime st_ctim;
  final int st_size;
  final int st_dev;
  final int st_ino;
  final int st_mode;
  final int st_uid;
  final int st_gid;

  _LibcStatAdapter({
    required this.st_mtim,
    required this.st_ctim,
    required this.st_size,
    required this.st_dev,
    required this.st_ino,
    required this.st_mode,
    required this.st_uid,
    required this.st_gid,
  });
}