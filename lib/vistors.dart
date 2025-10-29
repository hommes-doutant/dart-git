// lib/vistors.dart (Refactored for Installment 3)

import 'dart:async';
import 'dart:collection';
import 'package:path/path.dart' as p;
import 'package:tuple/tuple.dart';

import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/tree.dart';
import 'package:dart_git/storage/object_storage_cache.dart';
import 'package:dart_git/utils/file_mode.dart';

/// An abstract visitor for traversing every file (blob) in a commit history.
/// All methods are asynchronous to allow for I/O within the visitor logic.
abstract class TreeEntryVisitor {
  /// Called for each file (blob) encountered.
  /// Return `false` to stop the entire traversal immediately.
  Future<bool> visitTreeEntry({
    required GitCommit commit,
    required GitTree tree,
    required GitTreeEntry entry,
    required String filePath,
  }) async =>
      true;

  /// Called before traversing a tree.
  /// Return `false` to skip this tree and all its children.
  Future<bool> beforeTree(GitHash treeHash) async => true;

  /// Called before processing a commit.
  /// Return `false` to skip this commit entirely.
  Future<bool> beforeCommit(GitHash commitHash) async => true;

  /// Called after traversing a tree and all its children.
  Future<void> afterTree(GitTree tree) async {}

  /// Called after processing a commit and its entire tree.
  Future<void> afterCommit(GitCommit commit) async {}
}

extension Visitors on GitRepository {
  /// Traverses the commit and tree history starting from `fromCommitHash`,
  /// invoking the provided [visitor] for each component.
  Future<void> visitTree({
    required GitHash fromCommitHash,
    required TreeEntryVisitor visitor,
  }) async {
    // Note: The ObjectStorageCache should also be adapted to be async if it
    // performs caching that involves I/O, but for an in-memory cache, it can
    // wrap an async storage provider. We'll assume it's correctly adapted.
    final cachedObjStorage = ObjectStorageCache(storage: objStorage);

    // The synchronous commit iterator needs to be replaced with an async traversal.
    var queue = Queue<GitHash>.from([fromCommitHash]);
    var seenCommits = <GitHash>{};

    while (queue.isNotEmpty) {
      final commitHash = queue.removeFirst();
      if (seenCommits.contains(commitHash)) continue;
      seenCommits.add(commitHash);

      if (!await visitor.beforeCommit(commitHash)) {
        continue;
      }

      final commit = await cachedObjStorage.readCommit(commitHash);
      queue.addAll(commit.parents);

      // Now, traverse the tree for this commit
      var treeQueue = Queue<Tuple2<GitHash, String>>();
      treeQueue.add(Tuple2(commit.treeHash, ''));

      while (treeQueue.isNotEmpty) {
        final qt = treeQueue.removeFirst();
        final treeHash = qt.item1;
        final parentPath = qt.item2;

        if (!await visitor.beforeTree(treeHash)) {
          continue;
        }

        final tree = await cachedObjStorage.readTree(treeHash);
        for (var treeEntry in tree.entries) {
          final fullPath = parentPath.isEmpty
              ? treeEntry.name
              : '$parentPath/${treeEntry.name}';

          if (treeEntry.mode == GitFileMode.Dir) {
            treeQueue.add(Tuple2(treeEntry.hash, fullPath));
            continue;
          }

          final shouldContinue = await visitor.visitTreeEntry(
            commit: commit,
            tree: tree,
            entry: treeEntry,
            filePath: fullPath,
          );
          if (!shouldContinue) {
            return; // Exit the entire visit operation
          }
        }
        await visitor.afterTree(tree);
      }
      await visitor.afterCommit(commit);
    }
  }
}

/// A visitor that delegates calls to a list of other visitors.
class MultiTreeEntryVisitor extends TreeEntryVisitor {
  final List<TreeEntryVisitor> visitors;
  final Future<void> Function(GitCommit)? afterCommitCallback;

  MultiTreeEntryVisitor(this.visitors, {this.afterCommitCallback});

  @override
  Future<bool> visitTreeEntry({
    required GitCommit commit,
    required GitTree tree,
    required GitTreeEntry entry,
    required String filePath,
  }) async {
    for (var visitor in visitors) {
      if (!await visitor.visitTreeEntry(
          commit: commit, tree: tree, entry: entry, filePath: filePath)) {
        return false; // If any visitor wants to stop, we stop.
      }
    }
    return true;
  }

  @override
  Future<bool> beforeTree(GitHash treeHash) async {
    // If any visitor wants to process the tree, we should process it.
    var results = await Future.wait(visitors.map((v) => v.beforeTree(treeHash)));
    return results.any((r) => r);
  }

  @override
  Future<bool> beforeCommit(GitHash commitHash) async {
    // If any visitor wants to process the commit, we should process it.
    var results = await Future.wait(visitors.map((v) => v.beforeCommit(commitHash)));
    return results.any((r) => r);
  }

  @override
  Future<void> afterTree(GitTree tree) async {
    await Future.wait(visitors.map((v) => v.afterTree(tree)));
  }

  @override
  Future<void> afterCommit(GitCommit commit) async {
    await Future.wait(visitors.map((v) => v.afterCommit(commit)));
    if (afterCommitCallback != null) {
      await afterCommitCallback!(commit);
    }
  }
}