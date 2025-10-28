// lib/storage/object_storage_extensions.dart

import 'package:dart_git/exceptions.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/blob.dart';
import 'package:dart_git/plumbing/objects/commit.dart';
import 'package:dart_git/plumbing/objects/tree.dart';
import 'package:dart_git/utils/utils.dart';
import 'interfaces.dart';

extension ObjectStorageExtension on ObjectStorage {
  /// Resolves a pathspec (e.g., "path/to/file.txt") against a root tree.
  ///
  /// This method traverses the tree structure to find the [GitTreeEntry]
  /// corresponding to the given path.
  ///
  /// Throws [GitObjectWithRefSpecNotFound] if the path does not exist.
  Future<GitTreeEntry> refSpec(GitTree tree, String spec) async {
    if (spec.isEmpty || spec.startsWith('/')) {
      throw GitObjectWithRefSpecNotFound(spec);
    }

    final parts = splitPath(spec);
    final name = parts.item1;
    final remainingName = parts.item2;

    for (final leaf in tree.entries) {
      if (leaf.name == name) {
        if (remainingName.isEmpty) {
          // Found the final entry in the path.
          return leaf;
        }

        // The path continues, so this entry must be a tree.
        final obj = await read(leaf.hash);
        if (obj is GitTree) {
          // Recurse into the sub-tree with the rest of the path.
          return await refSpec(obj, remainingName);
        }

        // Path spec implies a directory, but this is a blob.
        throw GitObjectWithRefSpecNotFound(spec);
      }
    }

    // No entry matched the current part of the path.
    throw GitObjectWithRefSpecNotFound(spec);
  }

  /// Convenience method to read an object and cast it to a [GitBlob].
  ///
  /// Throws a [TypeError] if the object is not a blob.
  Future<GitBlob> readBlob(GitHash hash) async => await read(hash) as GitBlob;

  /// Convenience method to read an object and cast it to a [GitTree].
  ///
  /// Throws a [TypeError] if the object is not a tree.
  Future<GitTree> readTree(GitHash hash) async => await read(hash) as GitTree;

  /// Convenience method to read an object and cast it to a [GitCommit].
  ///
  /// Throws a [TypeError] if the object is not a commit.
  Future<GitCommit> readCommit(GitHash hash) async => await read(hash) as GitCommit;
}