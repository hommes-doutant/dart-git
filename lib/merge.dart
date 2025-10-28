// lib/merge.dart (Refactored for Installment 3)

import 'package:dart_git/dart_git.dart';
import 'package:dart_git/exceptions.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/tree.dart';
import 'package:dart_git/plumbing/reference.dart';
import 'package:dart_git/utils/file_mode.dart';

extension Merge on GitRepository {
  /// Merges the given commit into the current HEAD.
  ///
  /// This method performs the merge, creates a merge commit, and updates the
  /// working directory.
  Future<void> merge({
    required GitCommit theirCommit,
    required String message,
    required GitAuthor author,
    GitAuthor? committer,
  }) async {
    committer ??= author;

    // 1. Fetch the current HEAD commit
    final headRef = await head();
    if (headRef is! SymbolicReference) {
      throw GitMergeOnHashNotAllowed();
    }

    final headHash = (await resolveReference(headRef)).hash;
    final headCommit = await objStorage.readCommit(headHash);
    final theirHash = theirCommit.hash;

    // 2. Handle trivial cases: already up-to-date
    if (headHash == theirHash) {
      return;
    }

    // 3. Find the merge base
    final bases = await mergeBase(headCommit, theirCommit);
    if (bases.length > 1) {
      throw GitMergeTooManyBases();
    }

    if (bases.isNotEmpty) {
      final baseHash = bases.first.hash;

      // Already up-to-date (base is the other commit)
      if (baseHash == theirHash) {
        return;
      }

      // Fast-forward merge
      if (baseHash == headCommit.hash) {
        final branchNameRef = headRef.target;
        assert(branchNameRef.isBranch());

        final newRef = HashReference(branchNameRef, theirHash);
        await refStorage.saveRef(newRef);

        // Update working directory and index
        await checkout('.');
        return;
      }
    }

    // 4. Perform a three-way merge of the trees
    final baseTreeHash = bases.isNotEmpty ? bases.first.treeHash : null;
    final mergedTreeHash = await _combineTrees(
      headCommit.treeHash,
      theirCommit.treeHash,
      baseTreeHash,
    );

    // 5. Create the merge commit
    final parents = [headHash, theirHash];
    final commit = GitCommit.create(
      author: author,
      committer: committer,
      parents: parents,
      message: message,
      treeHash: mergedTreeHash,
    );
    await objStorage.writeObject(commit);

    // 6. Update HEAD and working directory to the new commit state
    await resetHard(commit.hash);
  }

  /// Recursively combines three trees: ours, theirs, and a common base.
  Future<GitHash> _combineTrees(
    GitHash ourTreeHash,
    GitHash theirTreeHash,
    GitHash? baseTreeHash,
  ) async {
    final ourTree = await objStorage.readTree(ourTreeHash);
    final theirTree = await objStorage.readTree(theirTreeHash);
    final baseTree = baseTreeHash != null ? await objStorage.readTree(baseTreeHash) : null;

    // Collect all unique entry names from all three trees
    final names = <String>{};
    ourTree.entries.forEach((e) => names.add(e.name));
    theirTree.entries.forEach((e) => names.add(e.name));
    baseTree?.entries.forEach((e) => names.add(e.name));

    var newEntries = <GitTreeEntry>[];
    for (var name in names) {
      final ourEntry = ourTree.entries.firstWhere((e) => e.name == name, orElse: () => null);
      final theirEntry = theirTree.entries.firstWhere((e) => e.name == name, orElse: () => null);
      final baseEntry = baseTree?.entries.firstWhere((e) => e.name == name, orElse: () => null);

      final newEntry = await _resolveConflicts(ourEntry, theirEntry, baseEntry);
      if (newEntry != null) {
        newEntries.add(newEntry);
      }
    }

    final newTree = GitTree.create(newEntries);
    return objStorage.writeObject(newTree);
  }

  /// Resolves the state of a single entry based on its presence and content
  /// in our tree, their tree, and the base tree.
  Future<GitTreeEntry?> _resolveConflicts(
    GitTreeEntry? ours,
    GitTreeEntry? theirs,
    GitTreeEntry? base,
  ) async {
    final oursExists = ours != null;
    final theirsExists = theirs != null;
    final baseExists = base != null;

    // Unmodified
    if (ours?.hash == theirs?.hash) return ours;
    if (ours?.hash == base?.hash) return theirs; // Changed in theirs only
    if (theirs?.hash == base?.hash) return ours; // Changed in ours only

    // Both added the same file independently.
    // If contents are identical, it's not a conflict.
    if (!baseExists && oursExists && theirsExists && ours.hash == theirs.hash) {
      return ours;
    }

    // Both modified a file.
    if (oursExists && theirsExists && baseExists) {
      // Simple conflict: both modified, but differently.
      // A real implementation would produce a conflict marker in the index and working tree.
      // For now, we'll implement the "ours" strategy as a default.
      // FIXME: Implement real merge conflict handling.
      return ours;
    }
    
    // One side deleted, one side modified. This is also a conflict.
    if ((!oursExists && theirsExists && baseExists) ||
        (oursExists && !theirsExists && baseExists)) {
       // FIXME: Implement real merge conflict handling.
       return ours; // 'ours' strategy: if we deleted it, it stays deleted.
    }
    
    // Default to 'ours' for any unhandled conflict.
    // This part is where strategies like 'ours', 'theirs', or conflict marking would happen.
    return ours;
  }
}