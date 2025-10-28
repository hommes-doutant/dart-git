// lib/storage/providers/storage_handle.dart

import 'package:equatable/equatable.dart';

/// An abstract handle to a storage entity (file or directory).
///
/// This is an opaque handle. The core Git logic should not know or care about
/// the underlying implementation (e.g., whether it's a local file path, a
/// content URI from Android's SAF, or a key in a cloud storage bucket).
abstract class StorageHandle {
  /// A URI-like string representation of the handle for identification and logging.
  String get uri;

  /// The final component of the path (the file or directory name).
  String get name;
}

/// The type of an entry in the storage system.
enum StorageEntryType {
  file,
  directory,
  notFound,
}

/// Metadata about a storage entity, similar to a `stat` result.
/// This is crucial for Git's index, which tracks modification times and sizes
/// to quickly detect changes in the working tree.
class StorageStat {
  final StorageEntryType type;
  final int size;
  final DateTime modificationTime;

  StorageStat({
    required this.type,
    required this.size,
    required this.modificationTime,
  });
}

/// A concrete implementation of [StorageHandle] for path-based filesystems.
/// This will be used by the legacy bridge implementation.
class PathBasedStorageHandle extends StorageHandle with EquatableMixin {
  /// The full, absolute path to the file or directory.
  final String path;

  PathBasedStorageHandle(this.path);

  @override
  String get uri => 'file://$path';

  @override
  String get name => path.split('/').last;

  @override
  List<Object?> get props => [path];
}