// lib/diff_commit.dart (Corrected)

import 'dart:collection';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:path/path.dart' as p;

import 'package:dart_git/diff_tree.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/commit.dart';
import 'package:dart_git/plumbing/objects/tree.dart';
import 'package:dart_git/storage/interfaces.dart';
import 'package:dart_git/utils/file_mode.dart';

// ... (CommitBlobChanges, Change, ChangeEntry, and _Item classes remain the same) ...
class CommitBlobChanges {
  final IList<Change> add;
  final IList<Change> remove;
  final IList<Change> modify;

  CommitBlobChanges({
    required Iterable<Change> add,
    required Iterable<Change> remove,
    required Iterable<Change> modify,
  })  : add = add.toIList(),
        remove = remove.toIList(),
        modify = modify.toIList();

  bool get isEmpty => add.isEmpty && modify.isEmpty && remove.isEmpty;
  List<Change> merged() => [...add, ...remove, ...modify];
  @override
  String toString() => 'CommitBlobChanges{\nadd: $add\nremove: $remove\nmodify: $modify';
}

class Change {
  final ChangeEntry? from;
  final ChangeEntry? to;
  Change({required this.from, required this.to}) { assert(from != null || to != null); }
  bool get delete => to == null;
  bool get add => from == null;
  bool get modify => to != null && from != null;
  String get path => from != null ? from!.path : to!.path;
  GitFileMode get mode => from != null ? from!.mode : to!.mode;
  GitHash get hash => from != null ? from!.hash : to!.hash;
  @override
  String toString() { /* ... */ return '';}
}

class ChangeEntry {
  final String path;
  final GitTree? tree;
  final GitTreeEntry? entry;
  ChangeEntry(this.path, this.tree, this.entry);
  GitHash get hash => entry!.hash;
  GitFileMode get mode => entry!.mode;
  @override
  String toString() => 'ChangeEntry{path: $path, hash: $hash}';
}

class _Item {
  final GitHash? fromTreeHash;
  final String? fromTreePath;
  final GitHash? toTreeHash;
  final String? toTreePath;
  _Item({ required this.fromTreeHash, required this.toTreeHash, required this.fromTreePath, required this.toTreePath });
  @override
  String toString() => '_Item{fromTreeHash: $fromTreeHash, fromTreePath: $fromTreePath, toTreeHash: $toTreeHash, toTreePath: $toTreePath}';
}


/// Asynchronously returns the changes needed to transform `fromCommit` to `toCommit`.
Future<CommitBlobChanges> diffCommits({
  required GitCommit fromCommit,
  required GitCommit toCommit,
  required ObjectStorage objStore,
}) async {
  var addedChanges = <Change>[];
  var removedChanges = <Change>[];
  var modifiedChanges = <Change>[];

  var queue = Queue<_Item>();
  queue.add(_Item(
    fromTreePath: '',
    toTreePath: '',
    fromTreeHash: fromCommit.treeHash,
    toTreeHash: toCommit.treeHash,
  ));

  while (queue.isNotEmpty) {
    var item = queue.removeFirst();

    if (item.fromTreeHash == item.toTreeHash) {
      continue;
    }

    // FIX: Await the results of the async readTree calls.
    GitTree? fromTree;
    if (item.fromTreeHash != null) {
      fromTree = await objStore.readTree(item.fromTreeHash!);
    }
    GitTree? toTree;
    if (item.toTreeHash != null) {
      toTree = await objStore.readTree(item.toTreeHash!);
    }

    var diffTreeResults = diffTree(from: fromTree, to: toTree);
    for (var result in diffTreeResults.merged()) {
      // Logic for handling blobs vs trees remains the same
      if (result.mode == GitFileMode.Dir) {
        String? fromTreePath;
        if (result.from != null) {
          fromTreePath = p.join(item.fromTreePath!, result.from!.name);
        }
        String? toTreePath;
        if (result.to != null) {
          toTreePath = p.join(item.toTreePath!, result.to!.name);
        }

        queue.add(_Item(
          fromTreePath: fromTreePath,
          toTreePath: toTreePath,
          fromTreeHash: result.from?.hash,
          toTreeHash: result.to?.hash,
        ));
      } else {
        if (result.modify) {
          var fromPath = p.join(item.fromTreePath!, result.from!.name);
          var toPath = p.join(item.toTreePath!, result.to!.name);
          var from = ChangeEntry(fromPath, fromTree, result.from);
          var to = ChangeEntry(toPath, toTree, result.to);
          modifiedChanges.add(Change(from: from, to: to));
        } else if (result.add) {
          var toPath = p.join(item.toTreePath!, result.to!.name);
          var to = ChangeEntry(toPath, toTree, result.to);
          addedChanges.add(Change(from: null, to: to));
        } else if (result.delete) {
          var fromPath = p.join(item.fromTreePath!, result.from!.name);
          var from = ChangeEntry(fromPath, fromTree, result.from);
          removedChanges.add(Change(from: from, to: null));
        }
      }
    }
  }

  var changes = CommitBlobChanges(
    add: addedChanges,
    remove: removedChanges,
    modify: modifiedChanges,
  );
  return changes;
}