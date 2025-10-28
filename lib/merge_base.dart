// lib/merge_base.dart (Refactored for Installment 3)

import 'dart:async';
import 'dart:collection';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/exceptions.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/utils/git_hash_set.dart';

extension MergeBase on GitRepository {
  /// Finds the best common ancestor(s) between two commits.
  /// Mimics `git merge-base <commit-a> <commit-b>`.
  Future<List<GitCommit>> mergeBase(GitCommit a, GitCommit b) async {
    // Sort commits to have a deterministic starting point
    var clist = [a, b];
    clist.sort(_commitDateDec);
    final newer = clist[0];
    final older = clist[1];

    // Get all ancestors of the newer commit. If the older commit is one of
    // them, then the older commit itself is the merge base.
    try {
      final newerHistory = await allAncestors(newer, shouldNotContain: older);

      // Find all commits in the older commit's history that are also
      // present in the newer commit's history.
      var results = <GitCommit>[];
      var queue = Queue<GitHash>.from([older.hash]);
      var seen = GitHashSet();

      while (queue.isNotEmpty) {
        final hash = queue.removeFirst();
        if (seen.contains(hash)) continue;
        seen.add(hash);

        final commit = await objStorage.readCommit(hash);

        // If this commit is in the newer history, it's a common ancestor.
        // We don't traverse its parents further because any of its parents
        // would be "less good" common ancestors.
        if (newerHistory.contains(commit.hash)) {
          results.add(commit);
        } else {
          queue.addAll(commit.parents);
        }
      }

      return await independents(results);

    } on GitShouldNotContainFound {
      // The `older` commit is a direct ancestor of `newer`.
      return [older];
    }
  }

  /// Traverses the history from `start` and collects all ancestor hashes.
  /// Throws [GitShouldNotContainFound] if `shouldNotContain` is encountered.
  Future<Set<GitHash>> allAncestors(
    GitCommit start, {
    required GitCommit shouldNotContain,
  }) async {
    if (start.hash == shouldNotContain.hash) {
      throw GitShouldNotContainFound();
    }

    var all = <GitHash>{};
    var queue = Queue<GitHash>.from([start.hash]);
    var seen = GitHashSet();

    while (queue.isNotEmpty) {
      final hash = queue.removeFirst();
      if (seen.contains(hash)) continue;
      seen.add(hash);

      if (hash == shouldNotContain.hash) {
        throw GitShouldNotContainFound();
      }
      
      all.add(hash);
      
      final commit = await objStorage.readCommit(hash);
      queue.addAll(commit.parents);
    }
    return all;
  }

  /// Checks if `ancestor` is a direct or indirect parent of `child`.
  /// Mimics `git merge-base --is-ancestor <ancestor> <child>`.
  Future<bool> isAncestor(GitCommit ancestor, GitCommit child) async {
    var queue = Queue<GitHash>.from([child.hash]);
    var seen = GitHashSet();

    while (queue.isNotEmpty) {
      final hash = queue.removeFirst();
      if (hash == ancestor.hash) return true;
      if (seen.contains(hash)) continue;
      seen.add(hash);
      
      final commit = await objStorage.readCommit(hash);
      queue.addAll(commit.parents);
    }
    return false;
  }

  /// From a list of commits, returns a subset containing only those that are not
  /// ancestors of any other commit in the list.
  /// Mimics `git merge-base --independent <commit-list>`.
  Future<List<GitCommit>> independents(List<GitCommit> commits) async {
    if (commits.length < 2) {
      return commits;
    }
    
    // Create a mutable copy to work with
    var independentCommits = List<GitCommit>.from(commits);
    
    var i = 0;
    while (i < independentCommits.length) {
      var currentCommit = independentCommits[i];
      var otherCommits = List<GitCommit>.from(independentCommits)..removeAt(i);
      
      var isAncestorOfAny = false;
      for (var other in otherCommits) {
        if (await isAncestor(currentCommit, other)) {
          isAncestorOfAny = true;
          break;
        }
      }
      
      if (isAncestorOfAny) {
        // This commit is an ancestor of another, so it's not independent. Remove it.
        independentCommits.removeAt(i);
        // Do not increment i, as the list has shifted.
      } else {
        // This commit is not an ancestor of any other, so keep it for now.
        i++;
      }
    }

    return independentCommits;
  }
}

int _commitDateDec(GitCommit a, GitCommit b) {
  return b.committer.date.compareTo(a.committer.date);
}

// Note: _removeDuplicates is no longer needed as the `independents` logic
// implicitly handles non-unique commits. If needed, it could be implemented
// with a GitHashSet.