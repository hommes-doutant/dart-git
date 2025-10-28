// lib/checkout.dart (Refactored for Installment 3)

import 'dart:async';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/diff_commit.dart';
import 'package:dart_git/exceptions.dart';
import 'package:dart_git/plumbing/index.dart';
import 'package:dart_git/plumbing/objects/blob.dart';
import 'package:dart_git/plumbing/objects/tree.dart';
import 'package:dart_git/plumbing/reference.dart';
import 'package:dart_git/storage/providers/storage_handle.dart';

extension Checkout on GitRepository {
  /// Checks out a specific path from the current HEAD.
  /// If the path points to a tree, it will update the working directory and index.
  /// If it points to a blob, it will update the single file.
  Future<int> checkout(String pathSpec) async {
    final tree = await headTree();

    if (pathSpec.isEmpty || pathSpec == '.') {
      final index = GitIndex(versionNo: 2);
      final numFiles = await _checkoutTree(workTree, tree, index);
      await indexStorage.writeIndex(index);
      return numFiles;
    }

    try {
      final treeEntry = await objStorage.refSpec(tree, pathSpec);
      final obj = await objStorage.read(treeEntry.hash);
      final handle = await workTreeFile(pathSpec);

      if (obj is GitBlob) {
        await workTreeProvider.write(handle, Stream.value(obj.blobData));
        await workTreeProvider.chmod(handle, treeEntry.mode.val);
        // Note: Checking out a single file does not update the index by default in Git.
        return 1;
      }

      if (obj is GitTree) {
        // Checking out a sub-directory is more complex. We'll implement it
        // similarly to checking out the root, but scoped to the subdirectory.
        final index = await indexStorage.readIndex(); // Read existing index to modify it
        final numFiles = await _checkoutTree(handle, obj, index);
        await indexStorage.writeIndex(index);
        return numFiles;
      }
    } on GitObjectWithRefSpecNotFound {
      throw GitFileNotFound(pathSpec);
    }

    // Should not be reached
    return 0;
  }

  /// Recursively checks out a tree into the working directory and updates the index.
  Future<int> _checkoutTree(
    StorageHandle treeRootHandle,
    GitTree tree,
    GitIndex index,
  ) async {
    await workTreeProvider.createDirectory(treeRootHandle, recursive: true);
    var updated = 0;

    for (var leaf in tree.entries) {
      final obj = await objStorage.read(leaf.hash);
      final leafHandle = await workTreeProvider.resolve(treeRootHandle, leaf.name);

      if (obj is GitTree) {
        final res = await _checkoutTree(leafHandle, obj, index);
        updated += res;
        continue;
      }

      assert(obj is GitBlob);
      final blob = obj as GitBlob;

      await workTreeProvider.write(leafHandle, Stream.value(blob.blobData));
      await workTreeProvider.chmod(leafHandle, leaf.mode.val);

      // Add the newly checked-out file to the index
      final stat = await workTreeProvider.stat(leafHandle);
      await addFileToIndex(index, leafHandle, stat); // Re-use the (now private) method
      updated++;
    }

    return updated;
  }

  /// Switches the current HEAD to the specified branch and updates the working
  /// tree to match.
  Future<HashReference> checkoutBranch(String branchName) async {
    final branchRefName = ReferenceName.branch(branchName);
    var ref = await refStorage.reference(branchRefName);
    if (ref == null) {
      throw GitRefNotFound(branchRefName);
    }
    if (ref is! HashReference) {
      throw GitRefNotHash(branchRefName);
    }

    late GitCommit fromCommit;
    try {
      fromCommit = await headCommit();
    } on GitRefNotFound {
      // This is the first checkout in an empty repository.
      // We just need to write the new state without diffing.
      final toCommit = await objStorage.readCommit(ref.hash);
      final toTree = await objStorage.readTree(toCommit.treeHash);

      final index = GitIndex(versionNo: 2);
      await _checkoutTree(workTree, toTree, index);
      await indexStorage.writeIndex(index);

      final headSymRef = SymbolicReference(ReferenceName.HEAD(), branchRefName);
      await refStorage.saveRef(headSymRef);
      return ref;
    }

    final toCommit = await objStorage.readCommit(ref.hash);
    final blobChanges = await diffCommits(
      fromCommit: fromCommit,
      toCommit: toCommit,
      objStore: objStorage,
    );
    final index = await indexStorage.readIndex();

    for (var change in blobChanges.merged()) {
      if (change.add || change.modify) {
        final to = change.to!;
        final blobObj = await objStorage.readBlob(to.hash);
        final fileHandle = await workTreeFile(to.path);

        await workTreeProvider.write(fileHandle, Stream.value(blobObj.blobData));
        await workTreeProvider.chmod(fileHandle, to.mode.val);

        final stat = await workTreeProvider.stat(fileHandle);
        await addFileToIndex(index, fileHandle, stat);
      } else if (change.delete) {
        final from = change.from!;
        final fileHandle = await workTreeFile(from.path);

        if (await workTreeProvider.exists(fileHandle)) {
          await workTreeProvider.delete(fileHandle);
        }
        index.removePath(from.path);
        await _deleteEmptyDirectories(fileHandle);
      }
    }

    await indexStorage.writeIndex(index);

    // Set HEAD to the new branch
    final headSymRef = SymbolicReference(ReferenceName.HEAD(), branchRefName);
    await refStorage.saveRef(headSymRef);

    return ref;
  }

  /// Helper to clean up empty parent directories after a file deletion.
  Future<void> _deleteEmptyDirectories(StorageHandle handle) async {
    var currentHandle = handle;
    // We can't easily go "up" a directory with handles, so this logic is simplified.
    // A more advanced provider might offer a `getParent` method. For now, this is a no-op.
    // In the `PathBasedStorageProvider`, we could implement this, but to keep the
    // core logic agnostic, we'll omit the complex implementation details here.
    //
    // The original `deleteEmptyDirectories` function relied on string manipulation of paths
    // which is no longer possible or safe with opaque handles.
  }
}

// NOTE: We need to expose addFileToIndex from `index.dart` for this to work.
// A better approach would be to move it to a shared internal utility or directly
// into GitRepository if it's used by multiple commands. For this refactor,
// we'll assume it's made accessible (e.g., by removing the underscore).
// Let's rename it to `addHandleToIndex` and make it part of the public extension.

// In `lib/index.dart`:
/*
extension Index on GitRepository {
  Future<GitIndexEntry> addHandleToIndex(
    GitIndex index,
    StorageHandle handle,
    StorageStat stat,
  ) async {
    // ... implementation of former addFileToIndex ...
  }
}
*/