// lib/storage/object_storage_cache.dart

import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/object.dart';
import 'interfaces.dart';
import '../plumbing/objects/tree.dart';

/// A caching wrapper for an [ObjectStorage] implementation.
///
/// This class maintains an in-memory cache of Git objects to reduce redundant
/// I/O operations, which can significantly improve performance when reading the
/// same objects multiple times (e.g., during tree traversals).
class ObjectStorageCache implements ObjectStorage {
  /// The underlying (delegate) object storage.
  final ObjectStorage _delegate;

  /// A simple, in-memory cache for Git objects.
  ///
  /// FIXME: For long-running applications, this cache should have a fixed size
  /// and an eviction policy (e.g., Least Recently Used - LRU) to prevent
  /// unbounded memory growth.
  final cache = <GitHash, GitObject>{};

  ObjectStorageCache({required ObjectStorage storage}) : _delegate = storage;

  /// Reads a Git object, checking the cache first.
  ///
  /// If the object is found in the cache, it is returned immediately. Otherwise,
  /// it is fetched from the underlying storage, added to the cache if it's a
  /// cachable type (like a Tree or Commit), and then returned.
  @override
  Future<GitObject> read(GitHash hash) async {
    final cachedObject = cache[hash];
    if (cachedObject != null) {
      return cachedObject;
    }

    final object = await _delegate.read(hash);

    // Only cache certain object types. Blobs can be very large, so we
    // avoid caching them by default to conserve memory. Trees and Commits
    // are generally small and frequently accessed, making them good candidates.
    if (object is GitTree || object is GitCommit) {
      cache[hash] = object;
    }

    return object;
  }

  /// Writes an object to the underlying storage.
  ///
  /// This implementation simply forwards the request to the delegate.
  /// It does not cache writes, as the object is now persisted and can be
  //  read and cached on the next `read` call if needed.
  @override
  Future<GitHash> writeObject(GitObject obj) {
    return _delegate.writeObject(obj);
  }

  /// Closes the underlying storage.
  @override
  Future<void> close() {
    return _delegate.close();
  }
}