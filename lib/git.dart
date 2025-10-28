// lib/git.dart

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

import 'package:dart_git/config.dart';
import 'package:dart_git/exceptions.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/commit.dart';
import 'package:dart_git/plumbing/objects/tree.dart';
import 'package:dart_git/plumbing/reference.dart';
import 'package:dart_git/storage/config_storage_fs.dart';
import 'package:dart_git/storage/index_storage_fs.dart';
import 'package:dart_git/storage/interfaces.dart';
import 'package:dart_git/storage/object_storage_fs.dart';
import 'package:dart_git/storage/reference_storage_fs.dart';
import 'package:dart_git/storage/providers/path_based_storage_provider.dart';
import 'package:dart_git/storage/providers/storage_handle.dart';
import 'package:dart_git/storage/providers/storage_provider.dart';
import 'package:dart_git/utils/git_hash_set.dart';
import 'package:dart_git/utils/local_fs_with_checks.dart';

// Public API exports. Consumers of the library will also need to update
// their code to be async to use the refactored methods.
export 'commit.dart';
export 'checkout.dart';
export 'merge_base.dart';
export 'merge.dart';
export 'remotes.dart';
export 'index.dart';
export 'vistors.dart';
export 'reset.dart';
export 'storage/object_storage_extensions.dart';

/// A Git Repository consists of 5 parts:
/// - Object Store: Manages Git objects (commits, trees, blobs, tags).
/// - Reference Store: Manages references (branches, tags).
/// - Index: The staging area for the next commit.
/// - Working Tree: The user-editable files on the filesystem.
/// - Config: Repository-specific configuration.
class GitRepository {
  /// The absolute path to the working tree directory. Always ends with a separator.
  late String workTree;

  /// The absolute path to the .git directory. Always ends with a separator.
  late String gitDir;

  /// The repository's configuration.
  late Config config;

  // Abstractions for storage and filesystem access.
  late GitStorageProvider storageProvider;
  late StorageHandle gitDirHandle;
  late FileSystem fs; // Kept for working tree operations until Installment 3.

  // Storage backends for different parts of the repository.
  late ReferenceStorage refStorage;
  late ObjectStorage objStorage;
  late IndexStorage indexStorage;
  late ConfigStorage configStorage;

  /// Internal constructor. Use `GitRepository.load` to create an instance.
  GitRepository._internal({
    required this.workTree,
    required this.gitDir,
    required this.fs,
    required this.storageProvider,
    required this.gitDirHandle,
  });

  /// Finds the root directory of a Git repository by searching upwards from the given path.
  /// Returns `null` if no Git repository is found.
  static String? findRootDir(String path, {FileSystem? fs}) {
    fs ??= const LocalFileSystemWithChecks();
    var currentPath = path;

    while (true) {
      final gitDir = p.join(currentPath, '.git');
      if (fs.isDirectorySync(gitDir)) {
        return currentPath;
      }

      if (currentPath == p.separator) break;
      currentPath = p.dirname(currentPath);
    }
    return null;
  }

  /// Loads a Git repository from a given path.
  ///
  /// This is the primary factory for creating a [GitRepository] instance for
  /// local filesystem access. It automatically sets up the necessary storage
  /// providers.
  static Future<GitRepository> load(
    String gitRootDir, {
    FileSystem? fs,
  }) async {
    fs ??= const LocalFileSystemWithChecks();

    final provider = PathBasedStorageProvider(fs);
    final workTreeHandle = PathBasedStorageHandle(gitRootDir);
    final gitDirHandle = await provider.resolve(workTreeHandle, '.git');

    if (!await provider.exists(gitDirHandle)) {
      throw InvalidRepoException(gitRootDir);
    }

    final repo = GitRepository._internal(
      workTree: gitRootDir.endsWith(p.separator) ? gitRootDir : '$gitRootDir${p.separator}',
      gitDir: (await provider.resolve(workTreeHandle, '.git') as PathBasedStorageHandle).path,
      fs: fs,
      storageProvider: provider,
      gitDirHandle: gitDirHandle,
    );

    // Initialize storage backends with the provider and .git directory handle.
    repo.objStorage = ObjectStorageFS(provider, gitDirHandle);
    repo.refStorage = ReferenceStorageFS(provider, gitDirHandle);
    repo.indexStorage = IndexStorageFS(provider, gitDirHandle);
    repo.configStorage = ConfigStorageFS(provider, gitDirHandle);

    if (!await repo.configStorage.exists()) {
      throw InvalidRepoException(gitRootDir);
    }

    await repo.reloadConfig();
    return repo;
  }

  /// Initializes a new Git repository at the specified path.
  static Future<void> init(
    String path, {
    FileSystem? fs,
    String defaultBranch = 'main',
  }) async {
    fs ??= const LocalFileSystem();

    var gitDir = p.join(path, '.git');
    if (fs.directory(gitDir).existsSync()) {
      throw GitRepoExists();
    }

    var dirsToCreate = ['branches', 'objects/pack', 'refs/heads', 'refs/tags'];
    for (var dir in dirsToCreate) {
      await fs.directory(p.join(gitDir, dir)).create(recursive: true);
    }

    await fs.file(p.join(gitDir, 'description')).writeAsString("Unnamed repository; edit this file 'description' to name the repository.\n");
    await fs.file(p.join(gitDir, refHead)).writeAsString('ref: refs/heads/$defaultBranch\n');

    var config = Config('');
    var core = config.getOrCreateSection('core');
    core.options['repositoryformatversion'] = '0';
    core.options['filemode'] = 'false';
    core.options['bare'] = 'false';

    await fs.file(p.join(gitDir, 'config')).writeAsString(config.serialize());
  }

  /// Closes any open resources.
  Future<void> close() async {
    await objStorage.close();
    await refStorage.close();
    await indexStorage.close();
  }

  /// Reloads the configuration from disk.
  Future<void> reloadConfig() async {
    config = await configStorage.readConfig();
  }

  /// Saves the current configuration to disk.
  Future<void> saveConfig() async {
    return configStorage.writeConfig(config);
  }

  /// Returns a list of all local branch names.
  Future<List<String>> branches() async {
    final refs = await refStorage.listReferences(refHeadPrefix);
    return refs.map((r) => r.name.branchName()!).toList();
  }

  /// Returns the name of the current branch. Throws [GitHeadDetached] if in a detached HEAD state.
  Future<String> currentBranch() async {
    final headRef = await head();
    switch (headRef) {
      case HashReference():
        throw GitHeadDetached();
      case SymbolicReference():
        return headRef.target.branchName()!;
    }
  }

  /// Sets the upstream for the current branch.
  Future<BranchConfig> setUpstreamTo(GitRemoteConfig remote, String remoteBranchName) async {
    final branchName = await currentBranch();
    return setBranchUpstreamTo(branchName, remote, remoteBranchName);
  }

  /// Sets the upstream for a specified local branch.
  Future<BranchConfig> setBranchUpstreamTo(String branchName, GitRemoteConfig remote, String remoteBranchName) async {
    var brConfig = config.branch(branchName) ?? BranchConfig(name: branchName);
    brConfig = BranchConfig(
      name: branchName,
      remote: remote.name,
      merge: ReferenceName.branch(remoteBranchName),
    );
    config.branches[branchName] = brConfig;
    await saveConfig();
    return brConfig;
  }

  /// Creates a new branch.
  Future<GitHash> createBranch(String name, {GitHash? hash, bool overwrite = false}) async {
    hash ??= await headHash();
    final branch = ReferenceName.branch(name);
    final ref = await refStorage.reference(branch);
    if (ref != null && !overwrite) {
      throw GitBranchAlreadyExists(name);
    }
    await refStorage.saveRef(HashReference(branch, hash));
    return hash;
  }

  /// Deletes a branch.
  Future<GitHash> deleteBranch(String branchName) async {
    final refName = ReferenceName.branch(branchName);
    final ref = await refStorage.reference(refName);
    if (ref == null) throw GitRefNotFound(refName);
    switch (ref) {
      case HashReference():
        await refStorage.deleteReference(refName);
        return ref.hash;
      case SymbolicReference():
        throw GitRefNotHash(refName);
    }
  }

  /// Returns the commit pointed to by a branch name, or `null` if the branch doesn't exist.
  Future<GitCommit?> branchCommit(String branchName) async {
    final refName = ReferenceName.branch(branchName);
    final ref = await refStorage.reference(refName);
    if (ref == null) return null;
    switch (ref) {
      case HashReference():
        return objStorage.readCommit(ref.hash);
      case SymbolicReference():
        throw GitRefNotHash(refName);
    }
  }

  /// Returns the current HEAD reference. Throws [GitMissingHEAD] on an empty repo.
  Future<Reference> head() async {
    final ref = await refStorage.reference(ReferenceName.HEAD());
    if (ref == null) throw GitMissingHEAD();
    return ref;
  }

  /// Returns the hash of the commit pointed to by HEAD. Throws on an empty repo.
  Future<GitHash> headHash() async {
    final ref = await resolveReference(await head());
    return ref.hash;
  }

  /// Returns the commit object pointed to by HEAD. Throws on an empty repo.
  Future<GitCommit> headCommit() async {
    final hash = await headHash();
    return objStorage.readCommit(hash);
  }

  /// Returns the root tree object of the commit pointed to by HEAD. Throws on an empty repo.
  Future<GitTree> headTree() async {
    final commit = await headCommit();
    return objStorage.readTree(commit.treeHash);
  }

  /// Recursively resolves a symbolic reference to a hash reference.
  Future<HashReference> resolveReference(Reference ref) async {
    switch (ref) {
      case HashReference():
        return ref;
      case SymbolicReference():
        final resolvedRef = await refStorage.reference(ref.target);
        if (resolvedRef == null) throw GitRefNotFound(ref.target);
        return resolveReference(resolvedRef);
    }
  }

  /// Resolves a reference name to a hash reference, or `null` if not found.
  Future<HashReference?> resolveReferenceName(ReferenceName refName) async {
    final ref = await refStorage.reference(refName);
    if (ref == null) return null;
    return resolveReference(ref);
  }

  /// Checks if there are local commits that can be pushed to the remote.
  Future<bool> canPush() async {
    if (config.remotes.isEmpty) return false;

    late Reference headRef;
    try {
      headRef = await head();
    } on GitRefNotFound {
      return false;
    }
    if (headRef is! SymbolicReference) return false;

    final brConfig = config.branch(headRef.target.branchName()!);
    if (brConfig?.merge == null || brConfig?.remote == null) return false;

    final resolvedHead = await resolveReference(headRef);
    final remoteRefName = ReferenceName.remote(brConfig!.remote!, brConfig.merge!.branchName()!);
    final remoteRef = await resolveReferenceName(remoteRefName);

    return resolvedHead.hash != remoteRef?.hash;
  }

  /// Counts the number of commits between `from` and `ancestor`. Returns -1 if unreachable.
  Future<int> countTillAncestor(GitHash from, GitHash ancestor) async {
    var seen = GitHashSet();
    var parents = <GitHash>[from];
    while (parents.isNotEmpty) {
      var sha = parents.removeAt(0);
      if (sha == ancestor) return seen.length;
      if (seen.contains(sha)) continue;

      seen.add(sha);
      final commit = await objStorage.readCommit(sha);
      for (var p in commit.parents) {
        if (!seen.contains(p)) parents.add(p);
      }
    }
    return -1;
  }

  /// Returns the number of commits the current branch is ahead of its remote tracking branch.
  Future<int> numChangesToPush() async {
    final headRef = await head();
    if (headRef is! SymbolicReference) return 0;

    final brConfig = config.branch(headRef.target.branchName()!);
    if (brConfig?.merge == null || brConfig?.remote == null) return 0;

    final remoteRefName = ReferenceName.remote(brConfig!.remote!, brConfig.merge!.branchName()!);
    final headHash = (await resolveReference(headRef)).hash;
    final remoteHash = (await resolveReferenceName(remoteRefName))?.hash;

    if (headHash == remoteHash || remoteHash == null) return 0;

    final aheadBy = await countTillAncestor(headHash, remoteHash);
    return aheadBy != -1 ? aheadBy : 0;
  }

  /// Normalizes a path to be absolute and within the repository's working tree.
  String normalizePath(String path) {
    if (!p.isAbsolute(path)) {
      path = path == '.' ? workTree : p.normalize(p.join(workTree, path));
    }
    if (!path.startsWith(workTree)) {
      throw PathSpecOutsideRepoException(pathSpec: path);
    }
    return path;
  }

  /// Converts an absolute path back to a relative pathspec from the repository root.
  String toPathSpec(String path) {
    if (path.startsWith(workTree)) {
      return path.substring(workTree.length);
    }
    if (p.isAbsolute(path)) {
      throw PathSpecOutsideRepoException(pathSpec: path);
    }
    return path;
  }
}