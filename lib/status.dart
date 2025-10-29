// lib/status.dart (Corrected)

import 'dart:async';
import 'dart:typed_data'; // Import for Uint8List
import 'package:collection/collection.dart';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/exceptions.dart'; // FIX: Added missing import
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/index.dart';
import 'package:dart_git/plumbing/objects/blob.dart';
import 'package:dart_git/plumbing/objects/tree.dart';
import 'package:dart_git/storage/providers/storage_handle.dart';
import 'package:dart_git/utils/file_mode.dart'; // Import for GitFileMode helpers
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

class GitStatusResult {
  final IList<GitFileStatus> staged;
  final IList<GitFileStatus> unstaged;
  final IList<String> untracked;
  GitStatusResult({ required this.staged, required this.unstaged, required this.untracked });
  bool get isClean => staged.isEmpty && unstaged.isEmpty && untracked.isEmpty;
}
class GitFileStatus {
  final String path;
  final GitFileStatusType headToIndex;
  final GitFileStatusType indexToWorkTree;
  GitFileStatus({ required this.path, this.headToIndex = GitFileStatusType.unmodified, this.indexToWorkTree = GitFileStatusType.unmodified });
}
enum GitFileStatusType { unmodified, added, deleted, modified }


extension Status on GitRepository {
  Future<GitStatusResult> status() async {
    GitTree? headTree;
    try {
      headTree = await this.headTree();
    } on GitMissingHEAD { // FIX: Now correctly recognized as a type
      // No HEAD yet, repository is empty.
    }
    final index = await indexStorage.readIndex();
    
    final headEntries = await _treeToPathMap(headTree);
    final indexEntries = {for (var e in index.entries) e.path: e};
    
    final stagedChanges = _compareMaps(headEntries, indexEntries);
    final workTreeEntries = await _workTreeToPathMap(workTree);
    final unstagedChanges = <GitFileStatus>[];
    final untrackedFiles = <String>[];
    
    final allIndexAndWorkTreePaths = {...indexEntries.keys, ...workTreeEntries.keys};

    for (final path in allIndexAndWorkTreePaths) {
      final indexEntry = indexEntries[path];
      final workTreeEntry = workTreeEntries[path];
      
      if (indexEntry == null && workTreeEntry != null) {
        untrackedFiles.add(path);
      } else if (indexEntry != null && workTreeEntry == null) {
        unstagedChanges.add(GitFileStatus(
          path: path,
          indexToWorkTree: GitFileStatusType.deleted,
        ));
      } else if (indexEntry != null && workTreeEntry != null) {
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

  Future<Map<String, GitHash>> _treeToPathMap(GitTree? tree) async {
    if (tree == null) return {};
    final map = <String, GitHash>{};

    Future<void> recurse(GitTree currentTree, String currentPath) async {
      for (final entry in currentTree.entries) {
        final path = currentPath.isEmpty ? entry.name : '$currentPath/${entry.name}';
        // FIX: Use the new helper getters
        if (entry.mode.isBlob) {
          map[path] = entry.hash;
        } else if (entry.mode.isTree) { // FIX: Use the new helper getters
          final subTree = await objStorage.readTree(entry.hash);
          await recurse(subTree, path);
        }
      }
    }
    await recurse(tree, '');
    return map;
  }
  
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
  
  Future<bool> _isWorkTreeFileModified(GitIndexEntry indexEntry, StorageStat workTreeStat) async {
    if (indexEntry.mTime.isAtSameMomentAs(workTreeStat.modificationTime) &&
        indexEntry.fileSize == workTreeStat.size) {
      return false;
    }
    
    final handle = await workTreeFile(indexEntry.path);
    final dataList = await workTreeProvider.read(handle).expand((b) => b).toList();
    // FIX: Explicitly create a Uint8List from the List<int>
    final data = Uint8List.fromList(dataList);
    final blob = GitBlob(data, null);
    
    return blob.hash != indexEntry.hash;
  }
}