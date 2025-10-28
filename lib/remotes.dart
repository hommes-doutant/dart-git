// lib/remotes.dart (Refactored for Installment 3)

import 'package:collection/collection.dart';

import 'package:dart_git/config.dart';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/exceptions.dart';
import 'package:dart_git/plumbing/reference.dart';

extension Remotes on GitRepository {
  /// Lists all branches for a given remote.
  Future<List<Reference>> remoteBranches(String remoteName) async {
    if (config.remote(remoteName) == null) {
      throw GitRemoteNotFound(remoteName);
    }

    final remoteRefsPrefix = '$refRemotePrefix$remoteName/';
    return refStorage.listReferences(remoteRefsPrefix);
  }

  /// Retrieves a specific remote branch reference.
  Future<HashReference> remoteBranch(
    String remoteName,
    String branchName,
  ) async {
    if (config.remote(remoteName) == null) {
      throw GitRemoteNotFound(remoteName);
    }

    final remoteRefName = ReferenceName.remote(remoteName, branchName);
    final ref = await refStorage.reference(remoteRefName);
    if (ref == null) throw GitRefNotFound(remoteRefName);

    switch (ref) {
      case HashReference():
        return ref;
      case SymbolicReference():
        throw GitRefNotHash(remoteRefName);
    }
  }

  /// Adds a new remote to the repository configuration.
  Future<GitRemoteConfig> addRemote(String name, String url) async {
    // config is already loaded in memory
    final existingRemote = config.remotes.firstWhereOrNull((r) => r.name == name);
    if (existingRemote != null) {
      throw GitRemoteAlreadyExists(name);
    }

    final remote = GitRemoteConfig.create(name: name, url: url);
    config.remotes.add(remote);

    await saveConfig(); // This is now an async call
    return remote;
  }

  /// Adds a new remote or updates the URL of an existing one.
  Future<GitRemoteConfig> addOrUpdateRemote(String name, String url) async {
    final i = config.remotes.indexWhere((r) => r.name == name);
    if (i == -1) {
      return addRemote(name, url);
    }

    config.remotes[i] = GitRemoteConfig(
      name: config.remotes[i].name,
      fetch: config.remotes[i].fetch,
      url: url,
    );
    await saveConfig();

    return config.remotes[i];
  }

  /// Removes a remote from the repository configuration and deletes its tracking branches.
  Future<GitRemoteConfig> removeRemote(String name) async {
    final i = config.remotes.indexWhere((r) => r.name == name);
    if (i == -1) {
      throw GitRemoteNotFound(name);
    }

    final remote = config.remotes.removeAt(i);
    await saveConfig();

    // Also remove all associated remote-tracking branches
    await refStorage.removeReferences(refRemotePrefix + name);
    // TODO: A future enhancement could be to garbage-collect objects that are no longer reachable.

    return remote;
  }

  /// Guesses the default branch (e.g., 'main' or 'master') for a given remote.
  /// This is useful for commands like `git clone` to know which branch to check out.
  Future<Reference?> guessRemoteHead(String remoteName) async {
    // See: https://git-scm.com/docs/git-remote#Documentation/git-remote.txt-emset-headem
    // The official way is to look for the symbolic ref 'refs/remotes/<remote>/HEAD'.
    
    final remoteHeadRefName = ReferenceName('$refRemotePrefix$remoteName/HEAD');
    final remoteHeadSymRef = await refStorage.reference(remoteHeadRefName);
    if (remoteHeadSymRef is SymbolicReference) {
      // The symbolic ref points to the actual default branch ref.
      // e.g., 'ref: refs/remotes/origin/main'
      return refStorage.reference(remoteHeadSymRef.target);
    }
    
    // Fallback logic if 'HEAD' symbolic-ref is not present.
    var branches = await remoteBranches(remoteName);
    if (branches.isEmpty) {
      return null;
    }
    if (branches.length == 1) {
      return branches[0];
    }
    
    // Look for common default branch names.
    var mainBranch = branches.firstWhereOrNull((b) => b.name.branchName() == 'main');
    if (mainBranch != null) return mainBranch;

    var masterBranch = branches.firstWhereOrNull((b) => b.name.branchName() == 'master');
    if (masterBranch != null) return masterBranch;
    
    // As a final fallback, sort alphabetically and return the first one.
    branches.sort((a, b) => a.name.branchName()!.compareTo(b.name.branchName()!));
    return branches[0];
  }
}