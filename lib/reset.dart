// lib/reset.dart (Refactored for Installment 3)

import 'dart:async';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/diff_commit.dart';
import 'package:dart_git/exceptions.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/reference.dart';
import 'package:dart_git/storage/providers/storage_handle.dart';

extension Reset on GitRepository {
  /// Resets the current HEAD to the specified commit hash. This operation
  /// modifies the current branch pointer, the index, and the working directory
  /// to match the target commit.
  Future<void> resetHard(GitHash hash) async {
    final fromCommit = await headCommit();
    final toCommit = await objStorage.readCommit(hash);

    // Calculate the difference between the current state and the target state.
    final changes = await diffCommits(
      fromCommit: fromCommit,
      toCommit: toCommit,
      objStore: objStorage,
    );

    // Apply the changes to the working directory.
    for (var change in changes.add) {
      final blob = await objStorage.readBlob(change.to!.hash);
      final handle = await workTreeFile(change.to!.path);
      
      await workTreeProvider.write(handle, Stream.value(blob.blobData));
      await workTreeProvider.chmod(handle, change.to!.mode.val);
    }

    for (var change in changes.remove) {
      final handle = await workTreeFile(change.from!.path);
      if (await workTreeProvider.exists(handle)) {
        // Assuming deletion is recursive for directories, though blobs should be files.
        await workTreeProvider.delete(handle, recursive: true);
      }
      // Directory cleanup is simplified due to opaque handles.
      await _deleteEmptyDirectories(handle);
    }

    for (var change in changes.modify) {
      final blob = await objStorage.readBlob(change.to!.hash);
      final handle = await workTreeFile(change.to!.path);

      await workTreeProvider.write(handle, Stream.value(blob.blobData));
      await workTreeProvider.chmod(handle, change.to!.mode.val);
    }

    // Update the current branch to point to the target commit hash.
    final headRef = await head();
    switch (headRef) {
      case HashReference():
        // Cannot reset a detached HEAD to a new commit this way.
        // A different command would be needed (like checkout).
        throw GitHeadDetached();
      case SymbolicReference():
        final branchNameRef = headRef.target;
        assert(branchNameRef.isBranch());

        final newRef = HashReference(branchNameRef, hash);
        await refStorage.saveRef(newRef);

        // After a hard reset, the index must also be reset to match the new HEAD.
        // The easiest way to do this is to perform a checkout of the entire tree.
        // This ensures the index is rebuilt from the target tree.
        await checkout('.');
    }
  }

  /// Helper to clean up empty parent directories after a file deletion.
  /// As noted in checkout.dart, this logic is simplified due to the opaque nature
  /// of StorageHandles. A provider with a `getParent` method would be needed for
  /// a full implementation.
  Future<void> _deleteEmptyDirectories(StorageHandle handle) async {
    // This remains a simplified placeholder.
    // The PathBasedStorageProvider could implement this, but the core logic
    // must remain agnostic.
  }
}