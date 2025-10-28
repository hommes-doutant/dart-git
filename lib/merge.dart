// lib/merge.dart (Corrected)

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

    final headRef = await head();
    if (headRef is! SymbolicReference) {
      throw GitMergeOnHashNotAllowed();
    }

    final headHash = (await resolveReference(headRef)).hash;
    final headCommit = await objStorage.readCommit(headHash);
    final theirHash = theirCommit.hash;

    if (headHash == theirHash) return;

    final bases = await mergeBase(headCommit, theirCommit);
    if (bases.length > 1) throw GitMergeTooManyBases();

    if (bases.isNotEmpty) {
      final baseHash = bases.first.hash;
      if (baseHash == theirHash) return;

      if (baseHash == headCommit.hash) {
        final branchNameRef = headRef.target;
        assert(branchNameRef.isBranch());

        final newRef = HashReference(branchNameRef, theirHash);
        await refStorage.saveRef(newRef);
        await checkout('.');
        return;
      }
    }

    final baseTreeHash = bases.isNotEmpty ? bases.first.treeHash : null;
    final mergedTreeHash = await _combineTrees(
      headCommit.treeHash,
      theirCommit.treeHash,
      baseTreeHash,
    );

    final parents = [headHash, theirHash];
    final commit = GitCommit.create(
      author: author,
      committer: committer,
      parents: parents,
      message: message,
      treeHash: mergedTreeHash,
    );
    await objStorage.writeObject(commit);
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

    // For efficient lookups, convert entry lists to maps from name to entry.
    final ourEntriesMap = {for (var e in ourTree.entries) e.name: e};
    final theirEntriesMap = {for (var e in theirTree.entries) e.name: e};
    final baseEntriesMap = {if (baseTree != null) for (var e in baseTree.entries) e.name: e};

    // Collect all unique entry names from all three trees
    final names = <String>{
      ...ourEntriesMap.keys,
      ...theirEntriesMap.keys,
      ...baseEntriesMap.keys,
    };

    var newEntries = <GitTreeEntry>[];
    for (var name in names) {
      final ourEntry = ourEntriesMap[name];
      final theirEntry = theirEntriesMap[name];
      final baseEntry = baseEntriesMap[name];

      // FIX: The `firstWhere` calls have been replaced with direct map lookups,
      // which correctly return `null` if the key is not found, fixing the errors.
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
    // Both are directories, recurse
    if (ours?.mode == GitFileMode.Dir && theirs?.mode == GitFileMode.Dir) {
        final newTreeHash = await _combineTrees(
            ours!.hash,
            theirs!.hash,
            base?.hash, // Base might not exist or might not be a directory
        );
        return GitTreeEntry(mode: GitFileMode.Dir, name: ours.name, hash: newTreeHash);
    }

    final oursExists = ours != null;
    final theirsExists = theirs != null;
    final baseExists = base != null;

    // Unmodified
    if (ours?.hash == theirs?.hash) return ours;
    if (ours?.hash == base?.hash) return theirs; // Changed in theirs only
    if (theirs?.hash == base?.hash) return ours; // Changed in ours only

    // Both added the same file independently.
    if (!baseExists && oursExists && theirsExists && ours.hash == theirs.hash) {
      return ours;
    }

    // Both modified a file.
    if (oursExists && theirsExists && baseExists) {
      // FIXME: Implement real merge conflict handling.
      return ours; // 'ours' strategy
    }
    
    // One side deleted, one side modified. This is also a conflict.
    if ((!oursExists && theirsExists && baseExists) ||
        (oursExists && !theirsExists && baseExists)) {
       // FIXME: Implement real merge conflict handling.
       return ours; // 'ours' strategy
    }
    
    // Default to 'ours' for any unhandled conflict.
    return ours;
  }
  
  Future<void> mergeCurrentTrackingBranch({required GitAuthor author}) async {
    final branchName = await currentBranch();
    final branchConfig = config.branch(branchName);
    if (branchConfig?.remote == null || branchConfig?.merge == null) {
      throw Exception("Branch '$branchName' has no tracking branch configured.");
    }

    final remoteBranchRef = await remoteBranch(
      branchConfig!.remote!,
      branchConfig.merge!.branchName()!,
    );
    final theirCommit = await objStorage.readCommit(remoteBranchRef.hash);

    await merge(
      theirCommit: theirCommit,
      author: author,
      message: 'Merge remote-tracking branch \'${branchConfig.remoteTrackingBranch()}\'',
    );
  }
}