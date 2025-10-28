// lib/status.dart (Refactored for Installment 3)

import 'dart:async';
import 'package:collection/collection.dart';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/index.dart';
import 'package:dart_git/plumbing/objects/blob.dart';
import 'package:dart_git/plumbing/objects/tree.dart';
import 'package:dart_git/storage/providers/storage_handle.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

/// Represents the status of files in the repository, comparing HEAD, the index,
/// and the working directory.
class GitStatusResult {
  /// Files that are different between the HEAD commit and the index.
  /// Represents "Changes to be committed".
  final IList<GitFileStatus> staged;

  /// Files that are different between the index and the working directory.
  /// Represents "Changes not staged for commit".
  final IList<GitFileStatus> unstaged;

  /// Files that are in the working directory but not in the index.
  /// Represents "Untracked files".
  final IList<String> untracked;

  GitStatusResult({
    required this.staged,
    required this.unstaged,
    required this.untracked,
  });

  bool get isClean => staged.isEmpty && unstaged.isEmpty && untracked.isEmpty;
}

/// The status of a single file.
class GitFileStatus {
  final String path;
  final GitFileStatusType headToIndex;
  final GitFileStatusType indexToWorkTree;

  GitFileStatus({
    required this.path,
    this.headToIndex = GitFileStatusType.unmodified,
    this.indexToWorkTree = GitFileStatusType.unmodified,
  });
}

/// The type of change for a file between two states.
enum GitFileStatusType {
  unmodified,
  added,
  deleted,
  modified,
}

extension Status on GitRepository {
  /// Computes the status of the repository.
  Future<GitStatusResult> status() async {
    // 1. Get the three states to compare: HEAD tree, index, and working tree files.
    GitTree? headTree;
    try {
      headTree = await this.headTree();
    } on GitMissingHEAD {
      // No HEAD yet, repository is empty. Treat it as an empty tree.
    }
    final index = await indexStorage.readIndex();
    
    // Convert the tree and index to maps for efficient lookup.
    final headEntries = await _treeToPathMap(headTree);
    final indexEntries = {for (var e in index.entries) e.path: e};
    
    // 2. Compare HEAD to Index to find staged changes.
    final stagedChanges = _compareMaps(headEntries, indexEntries);

    // 3. Compare Index to Working Directory to find unstaged changes and untracked files.
    final workTreeEntries = await _workTreeToPathMap(workTree);
    final unstagedChanges = <GitFileStatus>[];
    final untrackedFiles = <String>[];
    
    final allIndexAndWorkTreePaths = {...indexEntries.keys, ...workTreeEntries.keys};

    for (final path in allIndexAndWorkTreePaths) {
      final indexEntry = indexEntries[path];
      final workTreeEntry = workTreeEntries[path];
      
      if (indexEntry == null && workTreeEntry != null) {
        // In worktree, not in index -> Untracked
        untrackedFiles.add(path);
      } else if (indexEntry != null && workTreeEntry == null) {
        // In index, not in worktree -> Deleted
        unstagedChanges.add(GitFileStatus(
          path: path,
          indexToWorkTree: GitFileStatusType.deleted,
        ));
      } else if (indexEntry != null && workTreeEntry != null) {
        // In both, check for modification
        if (await _isWorkTreeFileModified(indexEntry, workTreeEntry)) {
          unstagedChanges.add(GitFileStatus(
            path: path,
            indexToWorkTree: GitFileStatusType.modified,
          ));
        }
      }
    }

    return GitStatusResult(
      staged: stagedChanges.toIList(),
      unstaged: unstagedChanges.toIList(),
      untracked: untrackedFiles.toIList(),
    );
  }

  /// Compares two maps of path -> GitHash to produce a list of status changes.
  List<GitFileStatus> _compareMaps(Map<String, GitHash> from, Map<String, GitIndexEntry> to) {
    final changes = <GitFileStatus>[];
    final allPaths = {...from.keys, ...to.keys};

    for (final path in allPaths) {
      final fromHash = from[path];
      final toEntry = to[path];
      
      if (fromHash == null && toEntry != null) {
        changes.add(GitFileStatus(path: path, headToIndex: GitFileStatusType.added));
      } else if (fromHash != null && toEntry == null) {
        changes.add(GitFileStatus(path: path, headToIndex: GitFileStatusType.deleted));
      } else if (fromHash != null && toEntry != null && fromHash != toEntry.hash) {
        changes.add(GitFileStatus(path: path, headToIndex: GitFileStatusType.modified));
      }
    }
    return changes;
  }

  /// Recursively traverses a GitTree and returns a flat map of file paths to their hashes.
  Future<Map<String, GitHash>> _treeToPathMap(GitTree? tree) async {
    if (tree == null) return {};
    final map = <String, GitHash>{};

    Future<void> recurse(GitTree currentTree, String currentPath) async {
      for (final entry in currentTree.entries) {
        final path = currentPath.isEmpty ? entry.name : '$currentPath/${entry.name}';
        if (entry.mode.isBlob) {
          map[path] = entry.hash;
        } else if (entry.mode.isTree) {
          final subTree = await objStorage.readTree(entry.hash);
          await recurse(subTree, path);
        }
      }
    }
    await recurse(tree, '');
    return map;
  }
  
  /// Traverses the working directory and returns a map of file paths to their stats.
  Future<Map<String, StorageStat>> _workTreeToPathMap(StorageHandle root) async {
    final map = <String, StorageStat>{};
    final gitDirRelativePath = await pathSpec(gitDir);
    
    Future<void> recurse(StorageHandle currentHandle, String currentPath) async {
      final children = await workTreeProvider.list(currentHandle);
      for (final child in children) {
        final path = currentPath.isEmpty ? child.name : '$currentPath/${child.name}';
        if (path.startsWith(gitDirRelativePath)) continue;
        
        final stat = await workTreeProvider.stat(child);
        if (stat.type == StorageEntryType.file) {
          map[path] = stat;
        } else if (stat.type == StorageEntryType.directory) {
          await recurse(child, path);
        }
      }
    }
    await recurse(root, '');
    return map;
  }
  
  /// Checks if a file in the working tree has been modified compared to its index entry.
  Future<bool> _isWorkTreeFileModified(GitIndexEntry indexEntry, StorageStat workTreeStat) async {
    // Git uses a few heuristics to avoid re-hashing every file.
    // 1. Check modification time and size.
    if (indexEntry.mTime.isAtSameMomentAs(workTreeStat.modificationTime) &&
        indexEntry.fileSize == workTreeStat.size) {
      return false;
    }
    
    // 2. If metadata differs, we have to hash the file to be certain.
    final handle = await workTreeFile(indexEntry.path);
    final data = await workTreeProvider.read(handle).expand((b) => b).toList();
    final blob = GitBlob(data, null); // Computes the hash
    
    return blob.hash != indexEntry.hash;
  }
}