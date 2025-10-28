// lib/dart_git_reader.dart

// This is the main entry point for the read-only Git library.

// Core Repository Class
import 'package:dart_git/git.dart';

// Storage Provider Abstractions (for custom backends)
import 'package:dart_git/storage/providers/storage_provider.dart';
import 'package:dart_git/storage/providers/storage_handle.dart';

// Core Git Data Models
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/commit.dart';
import 'package:dart_git/plumbing/objects/blob.dart';
import 'package:dart_git/plumbing/objects/tree.dart';
import 'package:dart_git/plumbing/reference.dart';

// Read-Only Extensions and Utilities
import 'package:dart_git/status.dart';
import 'package:dart_git/merge_base.dart';
import 'package:dart_git/remotes.dart';
import 'package:dart_git/vistors.dart';
import 'package:dart_git/plumbing/commit_iterator.dart';

// We explicitly DO NOT export:
// - commit.dart
// - index.dart
// - merge.dart
// - reset.dart
// - checkout.dart (as it has write operations)

/// A read-only view of a Git Repository.
///
/// This class provides a high-level API for inspecting a Git repository's state,
/// history, and files without performing any write operations.
///
/// It is built on a filesystem-agnostic storage layer, allowing it to work with
/// local files, Android's SAF, or any other storage backend via a custom
/// [GitStorageProvider].
///
/// For convenient use with the local filesystem, use the [GitRepositoryReader.local]
/// factory constructor.
class GitRepositoryReader extends GitRepository {
  /// The primary, fully-agnostic constructor for read-only operations.
  GitRepositoryReader.fromProviders({
    required super.workTreeProvider,
    required super.gitDirProvider,
    required super.workTree,
    required super.gitDir,
  }) : super.fromProviders();

  /// Convenience factory for creating a read-only repository view from a
  /// local filesystem path.
  static Future<GitRepositoryReader> local(String workTreePath) async {
    final repo = await GitRepository.local(workTreePath);
    return GitRepositoryReader.fromProviders(
      workTreeProvider: repo.workTreeProvider,
      gitDirProvider: repo.gitDirProvider,
      workTree: repo.workTree,
      gitDir: repo.gitDir,
    )..config = repo.config;
  }

  // Note: All read methods like `head()`, `branches()`, `status()`, `log()` (via commit iterators),
  // `remoteBranches()`, etc., are inherited from `GitRepository` and are available here.
  // The write methods are also technically inherited, but by not exporting their
  // extensions and documenting this class as read-only, we guide the user.
}