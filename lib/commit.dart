// lib/commit.dart (Refactored for Installment 3)

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'package:dart_git/dart_git.dart';
import 'package:dart_git/exceptions.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/index.dart';
import 'package:dart_git/plumbing/objects/tree.dart';
import 'package:dart_git/plumbing/reference.dart';
import 'package:dart_git/utils/file_mode.dart';

extension Commit on GitRepository {
  /// Creates a new commit from the current state of the index.
  ///
  /// Throws [GitEmptyCommit] if the new commit would have the exact same tree
  /// as its parent.
  Future<GitCommit> commit({
    required String message,
    required GitAuthor author,
    GitAuthor? committer,
    bool addAll = false,
  }) async {
    committer ??= author;

    if (addAll) {
      // The `add` command now needs to be awaited.
      // We assume adding the root of the worktree is the intended behavior.
      await add('.');
    }

    final index = await indexStorage.readIndex();
    if (index.entries.isEmpty) {
      throw GitEmptyCommit();
    }

    final treeHash = await writeTree(index);
    var parents = <GitHash>[];

    try {
      final headRef = await head();
      final parentRef = await resolveReference(headRef);
      parents.add(parentRef.hash);
    } on GitMissingHEAD {
      // This is the first commit, no parents.
    } on GitRefNotFound {
      // This is the first commit, no parents.
    }

    // Check if the commit is identical to its parent
    if (parents.isNotEmpty) {
      final parentCommit = await objStorage.readCommit(parents.first);
      if (parentCommit.treeHash == treeHash) {
        throw GitEmptyCommit();
      }
    }

    final commit = GitCommit.create(
      author: author,
      committer: committer,
      parents: parents,
      message: message,
      treeHash: treeHash,
    );
    final hash = await objStorage.writeObject(commit);

    // Update the ref of the current branch
    final branchName = await currentBranch();
    final newRef = HashReference(ReferenceName.branch(branchName), hash);
    await refStorage.saveRef(newRef);

    return commit;
  }

  /// Creates a tree object from the given index, writing all necessary
  /// sub-tree objects to the object store. Returns the hash of the root tree.
  Future<GitHash> writeTree(GitIndex index) async {
    var allTreeDirs = {''};
    var treeObjects = {'': GitTree.create()};

    for (var entry in index.entries) {
      var fullPath = entry.path;
      var fileName = p.basename(fullPath);
      var dirName = p.dirname(fullPath);
      if (dirName == '.') dirName = '';

      // Create all parent directory tree objects in memory if they don't exist
      var currentDir = dirName;
      while (currentDir != '' && !allTreeDirs.contains(currentDir)) {
          allTreeDirs.add(currentDir);
          treeObjects.putIfAbsent(currentDir, () => GitTree.create());
          currentDir = p.dirname(currentDir);
          if (currentDir == '.') currentDir = '';
      }
      
      // Add the file entry to its immediate parent tree
      final existingEntries = treeObjects[dirName]!.entries;
      final newEntry = GitTreeEntry(mode: entry.mode, name: fileName, hash: entry.hash);
      treeObjects[dirName] = GitTree.create(existingEntries.add(newEntry));
    }
    
    // Connect parent trees to their children (sub-trees)
    for (final dir in allTreeDirs) {
      if (dir == '') continue;

      final parentDir = p.dirname(dir) == '.' ? '' : p.dirname(dir);
      final folderName = p.basename(dir);
      final parentTree = treeObjects[parentDir]!;

      // If the sub-directory isn't already in the parent tree, add a placeholder
      if (!parentTree.entries.any((e) => e.name == folderName)) {
        final placeholderEntry = GitTreeEntry(
          mode: GitFileMode.Dir,
          name: folderName,
          hash: GitHash.zero(), // We'll replace this hash later
        );
        treeObjects[parentDir] = GitTree.create(parentTree.entries.add(placeholderEntry));
      }
    }

    var hashMap = <String, GitHash>{};

    // Sort directories from deepest to shallowest to write sub-trees first
    var sortedDirs = allTreeDirs.toList();
    sortedDirs.sort((a, b) => b.split('/').length.compareTo(a.split('/').length));

    for (var dir in sortedDirs) {
      var tree = treeObjects[dir]!;
      var entries = tree.entries.unlock; // Get a mutable copy

      for (var i = 0; i < entries.length; i++) {
        var leaf = entries[i];
        if (leaf.mode == GitFileMode.Dir) {
          final subTreePath = p.join(dir, leaf.name);
          final subTreeHash = hashMap[subTreePath];
          if (subTreeHash == null) {
            throw Exception('Internal error: subtree hash for $subTreePath not found');
          }
          // Replace placeholder hash with the actual written hash
          entries[i] = GitTreeEntry(mode: leaf.mode, name: leaf.name, hash: subTreeHash);
        }
      }

      // Re-create the tree with updated entries and write it to the object store
      final finalTree = GitTree.create(entries);
      final hash = await objStorage.writeObject(finalTree);
      hashMap[dir] = hash;
    }

    return hashMap['']!;
  }
}

// The dirSortFunc is no longer needed due to the simpler sorting logic above.