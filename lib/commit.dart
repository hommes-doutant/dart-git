// lib/commit.dart (Corrected)

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
  /// ... (commit method remains the same as the last version) ...
  Future<GitCommit> commit({
    required String message,
    required GitAuthor author,
    GitAuthor? committer,
    bool addAll = false,
  }) async {
    committer ??= author;

    if (addAll) {
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
      // First commit
    } on GitRefNotFound {
      // First commit
    }

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

    final branchName = await currentBranch();
    final newRef = HashReference(ReferenceName.branch(branchName), hash);
    await refStorage.saveRef(newRef);

    return commit;
  }

  /// Creates a tree object from the given index, writing all necessary
  /// sub-tree objects to the object store. Returns the hash of the root tree.
  Future<GitHash> writeTree(GitIndex index) async {
    var allTreeDirs = <String>{''};
    var treeObjects = <String, List<GitTreeEntry>>{'': []};

    // 1. Populate in-memory tree structures from the flat index
    for (var entry in index.entries) {
      var fullPath = entry.path;
      var fileName = p.basename(fullPath);
      var dirName = p.dirname(fullPath);
      if (dirName == '.') dirName = '';

      // Create all parent directory entries if they don't exist
      var pathParts = dirName.split('/').where((part) => part.isNotEmpty);
      var currentPath = '';
      for (var part in pathParts) {
        var parentPath = currentPath;
        currentPath = currentPath.isEmpty ? part : '$currentPath/$part';
        
        allTreeDirs.add(currentPath);
        treeObjects.putIfAbsent(currentPath, () => []);
        
        var parentEntries = treeObjects[parentPath]!;
        if (!parentEntries.any((e) => e.name == part)) {
          parentEntries.add(GitTreeEntry(
            mode: GitFileMode.Dir,
            name: part,
            hash: GitHash.zero(), // Placeholder hash
          ));
        }
      }
      
      // Add the file entry to its immediate parent
      treeObjects[dirName]!.add(GitTreeEntry(
        mode: entry.mode,
        name: fileName,
        hash: entry.hash,
      ));
    }

    var hashMap = <String, GitHash>{};
    var sortedDirs = allTreeDirs.toList();
    // 2. Sort directories correctly: from deepest to shallowest, then alphabetically
    sortedDirs.sort(dirSortFunc);

    // 3. Write trees from the bottom up (deepest first)
    for (var dir in sortedDirs.reversed) {
      var entries = treeObjects[dir]!;
      
      // Replace placeholder hashes for subdirectories
      for (var i = 0; i < entries.length; i++) {
        var leaf = entries[i];
        if (leaf.mode == GitFileMode.Dir) {
          final subTreePath = dir.isEmpty ? leaf.name : '$dir/${leaf.name}';
          final subTreeHash = hashMap[subTreePath];
          if (subTreeHash == null) {
            throw Exception('Internal error: subtree hash for $subTreePath not found');
          }
          entries[i] = GitTreeEntry(
            mode: leaf.mode,
            name: leaf.name,
            hash: subTreeHash,
          );
        }
      }

      // Git requires tree entries to be sorted!
      entries.sort((a, b) {
        // Git's sorting is a bit special: directories are sorted as if their
        // name was "name/", which places them before files of the same name.
        var aName = a.mode == GitFileMode.Dir ? '${a.name}/' : a.name;
        var bName = b.mode == GitFileMode.Dir ? '${b.name}/' : b.name;
        return aName.compareTo(bName);
      });
      
      // Create and write the final tree object
      final finalTree = GitTree.create(entries);
      final hash = await objStorage.writeObject(finalTree);
      hashMap[dir] = hash;
    }

    return hashMap['']!;
  }
}

/// Sorts directory paths correctly for tree construction.
///
/// 1. Sorts by depth (number of path separators).
/// 2. For paths at the same depth, sorts lexicographically.
///
/// This ensures that when processing in reverse (bottom-up), we always
/// compute the hash of a child directory before its parent.
@visibleForTesting
int dirSortFunc(String a, String b) {
  var aCnt = '/'.allMatches(a).length;
  var bCnt = '/'.allMatches(b).length;
  if (aCnt != bCnt) {
    return aCnt.compareTo(bCnt);
  }
  if (a.isEmpty && b.isEmpty) return 0;
  if (a.isEmpty) return -1;
  if (b.isEmpty) return 1;
  
  return a.compareTo(b);
}