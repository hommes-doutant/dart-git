// FILE: lib/dart_git.dart
/// A pure Dart implementation of Git.
///
/// This is the main entry point for the library, exporting all the major
/// classes and functionality.
library dart_git;

//
// High-Level Repository objects
//
export 'git.dart';
export 'git_async.dart';

//
// Storage Provider Abstractions (for custom backends)
//
export 'storage/providers/storage_provider.dart';
export 'storage/providers/storage_handle.dart';

//
// Concrete provider for the local filesystem (most common use case)
//
export 'storage/providers/path_based_storage_provider.dart';

//
// Core Git Data Models and Plumbing objects
//
export 'plumbing/git_hash.dart';
export 'plumbing/objects/object.dart';
export 'plumbing/objects/commit.dart';
export 'plumbing/objects/blob.dart';
export 'plumbing/objects/tree.dart';
export 'plumbing/reference.dart';
export 'plumbing/index.dart';

//
// Low-level plumbing for advanced use cases and testing
//
export 'plumbing/idx_file.dart';
export 'plumbing/pack_file.dart';

//
// Configuration Models
//
export 'config.dart';

//
// Exceptions
//
export 'exceptions.dart';

//
// High-level utilities and visitors
//
export 'file_mtime_builder.dart';
export 'blob_ctime_builder.dart';
export 'diff_commit.dart';
export 'diff_tree.dart';
export 'status.dart';