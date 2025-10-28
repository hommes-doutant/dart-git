// lib/blob_ctime_builder.dart (Corrected)

import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/tree.dart';
import 'package:dart_git/utils/date_time.dart';
import 'package:dart_git/utils/git_hash_set.dart';

/// Fetches the creation time for each blob by traversing the commit history.
class BlobCTimeBuilder extends TreeEntryVisitor {
  var processedTrees = GitHashSet();
  var processedCommits = GitHashSet();
  var map = <GitHash, GDateTime>{};

  BlobCTimeBuilder({
    Set<GitHash>? processedTrees,
    Set<GitHash>? processedCommits,
    Map<GitHash, GDateTime>? map,
  }) : map = map ?? {} {
    this.processedCommits = GitHashSet.from(processedCommits);
    this.processedTrees = GitHashSet.from(processedTrees);
  }

  void update(BlobCTimeBuilder b) {
    processedTrees = b.processedTrees;
    processedCommits = b.processedCommits;
    map = b.map;
  }

  @override
  Future<bool> beforeTree(GitHash treeHash) async {
    return !processedTrees.contains(treeHash);
  }

  @override
  Future<void> afterTree(GitTree tree) async {
    processedTrees.add(tree.hash);
  }

  @override
  Future<bool> beforeCommit(GitHash commitHash) async {
    return !processedCommits.contains(commitHash);
  }

  @override
  Future<void> afterCommit(GitCommit commit) async {
    processedCommits.add(commit.hash);
  }

  @override
  Future<bool> visitTreeEntry({
    required GitCommit commit,
    required GitTree tree,
    required GitTreeEntry entry,
    required String filePath,
  }) async {
    final commitTime = commit.author.date as GDateTime;

    var time = commitTime;
    var et = map[entry.hash];
    if (et != null) {
      time = et.isBefore(time) ? et : time;
    }

    map[entry.hash] = time;
    return true; // Continue traversal
  }

  GDateTime? cTime(GitHash hash) => map[hash];
}