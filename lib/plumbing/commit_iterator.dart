// lib/plumbing/commit_iterator.dart (Refactored for Installment 3)

import 'dart:async';
import 'dart:collection';

import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/commit.dart';
import 'package:dart_git/storage/interfaces.dart';
import 'package:dart_git/utils/git_hash_set.dart';

/// Traverses the commit graph in Breadth-First Search (BFS) order, returning
/// a stream of [GitCommit] objects.
Stream<GitCommit> commitIteratorBFS({
  required ObjectStorage objStorage,
  required GitHash from,
}) async* {
  var queue = Queue<GitHash>.from([from]);
  var seen = GitHashSet();

  while (queue.isNotEmpty) {
    final hash = queue.removeFirst();
    if (seen.contains(hash)) {
      continue;
    }
    seen.add(hash);

    try {
      final commit = await objStorage.readCommit(hash);
      queue.addAll(commit.parents);
      yield commit;
    } on GitObjectNotFound {
      // If a commit object is missing, we just stop traversing down that path.
      continue;
    }
  }
}

typedef CommitFilter = FutureOr<bool> Function(GitCommit commit);
typedef CommitHashFilter = FutureOr<bool> Function(GitHash commitHash);

final _allCommitsValidFilter = (GitCommit _) => true;
final _allCommitsNotValidFilter = (GitCommit _) => false;
final _doNotSkip = (GitHash _) => false;

/// Traverses the commit graph in BFS order with filtering capabilities,
/// returning a stream of [GitCommit] objects.
Stream<GitCommit> commitIteratorBFSFiltered({
  required ObjectStorage objStorage,
  required GitHash from,
  CommitFilter? isValid,
  CommitFilter? isLimit,
  CommitHashFilter? skipCommitHash,
}) async* {
  isValid ??= _allCommitsValidFilter;
  isLimit ??= _allCommitsNotValidFilter;
  skipCommitHash ??= _doNotSkip;

  var queue = Queue<GitHash>.from([from]);
  var seen = GitHashSet();

  while (queue.isNotEmpty) {
    final hash = queue.removeFirst();
    if (seen.contains(hash) || await skipCommitHash(hash)) {
      continue;
    }
    seen.add(hash);

    try {
      final commit = await objStorage.readCommit(hash);
      
      if (!await isLimit(commit)) {
        queue.addAll(commit.parents);
      }
      if (await isValid(commit)) {
        yield commit;
      }
    } on GitObjectNotFound {
      continue;
    }
  }
}

/// Traverses the commit graph in Pre-Order traversal, returning a stream of
/// [GitCommit] objects.
Stream<GitCommit> commitPreOrderIterator({
  required ObjectStorage objStorage,
  required GitHash from,
}) async* {
  var stack = <GitHash>[from];
  var seen = GitHashSet();

  while (stack.isNotEmpty) {
    final hash = stack.removeLast();
    if (seen.contains(hash)) {
      continue;
    }
    seen.add(hash);

    try {
      final commit = await objStorage.readCommit(hash);
      // Add parents in reverse order to maintain correct pre-order traversal
      stack.addAll(commit.parents.reversed);
      yield commit;
    } on GitObjectNotFound {
      continue;
    }
  }
}