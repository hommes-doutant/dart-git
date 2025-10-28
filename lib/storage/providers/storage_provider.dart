// lib/storage/providers/storage_provider.dart

import 'dart:typed_data';
import 'storage_handle.dart';

/// An abstract interface for all filesystem and storage operations.
///
/// Implementations of this class provide the bridge between the platform-agnostic
/// Git logic and a specific storage backend (e.g., local disk, Android's SAF,
/// an in-memory filesystem for tests).
///
/// All operations are asynchronous to support network or otherwise non-blocking
/// storage backends.
abstract class GitStorageProvider {
  /// Resolves a relative path string against a base handle to produce a new handle.
  ///
  /// This is the primary mechanism for navigating a directory structure.
  /// For example, `resolve(gitDirHandle, 'refs/heads/main')`.
  Future<StorageHandle> resolve(StorageHandle base, String relativePath);

  /// Reads the entire content of a file handle as a stream of bytes.
  /// Using a stream is critical for handling large Git objects and packfiles
  /// without consuming excessive memory.
  Stream<List<int>> read(StorageHandle handle);

  /// Writes a stream of bytes to a file handle.
  ///
  /// The implementation should ensure that the target directory exists.
  Future<void> write(StorageHandle handle, Stream<List<int>> data);

  /// Checks if an entity exists at the given handle.
  Future<bool> exists(StorageHandle handle);

  /// Deletes a file or directory.
  /// If [recursive] is true and the handle points to a directory, all its
  /// contents will be deleted.
  Future<void> delete(StorageHandle handle, {bool recursive = false});

  /// Lists the child entities within a directory handle.
  Future<List<StorageHandle>> list(StorageHandle handle);

  /// Retrieves metadata for a storage entity.
  Future<StorageStat> stat(StorageHandle handle);

  /// Creates a directory at the given handle.
  /// If [recursive] is true, creates all non-existent parent directories.
  Future<void> createDirectory(StorageHandle handle, {bool recursive = false});

  /// Changes the mode of a file, primarily for setting the executable bit.
  ///
  /// This may be a no-op on filesystems that don't support POSIX permissions.
  Future<void> chmod(StorageHandle handle, int mode);
  
  /// Reads a specific byte range from a file handle.
  ///
  /// This is the key method that enables random-access I/O for packfiles
  /// without loading the entire file into memory. Providers should implement
  /// this as efficiently as possible (e.g., using `RandomAccessFile` for local
  /// files or HTTP Range Requests for network files).
  ///
  /// Throws an exception if the range is invalid or the handle is not a file.
  Future<Uint8List> readRange(StorageHandle handle, int start, int end);
}