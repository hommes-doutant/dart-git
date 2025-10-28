// lib/git.dart

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
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

export 'commit.dart';
export 'checkout.dart';
export 'merge_base.dart';
export 'merge.dart';
export 'remotes.dart';
export 'index.dart';
export 'vistors.dart';
export 'reset.dart';
export 'storage/object_storage_extensions.dart';

class GitRepository {
  /// The abstract provider for the working tree (user's files).
  final GitStorageProvider workTreeProvider;

  /// The abstract provider for the .git directory.
  final GitStorageProvider gitDirProvider;

  /// A handle to the root of the working tree.
  final StorageHandle workTree;

  /// A handle to the root of the .git directory.
  final StorageHandle gitDir;

  late Config config;

  // Storage backends are initialized with providers.
  late ReferenceStorage refStorage;
  late ObjectStorage objStorage;
  late IndexStorage indexStorage;
  late ConfigStorage configStorage;

  /// The primary, fully-agnostic constructor.
  /// Consumers must provide providers and handles for both the working tree
  /// and the .git directory.
  GitRepository.fromProviders({
    required this.workTreeProvider,
    required this.gitDirProvider,
    required this.workTree,
    required this.gitDir,
  }) {
    objStorage = ObjectStorageFS(gitDirProvider, gitDir);
    refStorage = ReferenceStorageFS(gitDirProvider, gitDir);
    indexStorage = IndexStorageFS(gitDirProvider, gitDir);
    configStorage = ConfigStorageFS(gitDirProvider, gitDir);
  }

  /// Convenience factory for the common case of a local filesystem repository.
  /// This preserves the simple, path-based API for existing users.
  static Future<GitRepository> local(String workTreePath, {FileSystem? fs}) async {
    fs ??= const LocalFileSystem();

    // The same provider is used for both since they are on the same filesystem.
    final provider = PathBasedStorageProvider(fs);

    final workTreeHandle = PathBasedStorageHandle(p.absolute(workTreePath));
    final gitDirHandle = await provider.resolve(workTreeHandle, '.git');

    // Manually check for a valid repo before constructing.
    final configHandle = await provider.resolve(gitDirHandle, 'config');
    if (!await provider.exists(gitDirHandle) || !await provider.exists(configHandle)) {
      throw InvalidRepoException(workTreePath);
    }

    final repo = GitRepository.fromProviders(
      workTreeProvider: provider,
      gitDirProvider: provider,
      workTree: workTreeHandle,
      gitDir: gitDirHandle,
    );

    await repo.reloadConfig();
    return repo;
  }

  /// A static method to find the root of a Git repository from a given path.
  /// Returns null if no repository is found.
  static Future<String?> findRootDir(String path, {FileSystem? fs}) async {
    fs ??= const LocalFileSystem();
    var currentPath = p.absolute(path);

    while (true) {
      var gitDir = p.join(currentPath, '.git');
      if (await fs.isDirectory(gitDir)) {
        return currentPath;
      }

      var parent = p.dirname(currentPath);
      if (parent == currentPath) { // Reached the root of the filesystem
        return null;
      }
      currentPath = parent;
    }
  }

  /// Initializes an empty Git repository at the specified path on the local filesystem.
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

    var dirsToCreate = [
      'branches',
      'objects/pack',
      'refs/heads',
      'refs/tags',
    ];
    for (var dir in dirsToCreate) {
      await fs.directory(p.join(gitDir, dir)).create(recursive: true);
    }

    await fs.file(p.join(gitDir, 'description')).writeAsString(
        "Unnamed repository; edit this file 'description' to name the repository.\n");
    await fs
        .file(p.join(gitDir, refHead))
        .writeAsString('ref: refs/heads/$defaultBranch\n');

    var config = Config('');
    var core = config.getOrCreateSection('core');
    core.options['repositoryformatversion'] = '0';
    core.options['filemode'] = 'false';
    core.options['bare'] = 'false';

    await fs.file(p.join(gitDir, 'config')).writeAsString(config.serialize());
  }

  Future<void> reloadConfig() async {
    config = await configStorage.readConfig();
  }

  Future<void> saveConfig() async {
    return configStorage.writeConfig(config);
  }

  // All methods that perform I/O are now async.
  Future<List<String>> branches() async {
    final refs = await refStorage.listReferences(refHeadPrefix);
    return refs.map((r) => r.name.branchName()!).toList();
  }

  Future<String> currentBranch() async {
    final headRef = await head();
    switch (headRef) {
      case HashReference():
        throw GitHeadDetached();
      case SymbolicReference():
        return headRef.target.branchName()!;
    }
  }

  Future<Reference> head() async {
    final ref = await refStorage.reference(ReferenceName.HEAD());
    if (ref == null) throw GitMissingHEAD();
    return ref;
  }

  Future<GitHash> headHash() async {
    final ref = await resolveReference(await head());
    return ref.hash;
  }

  Future<GitCommit> headCommit() async {
    final hash = await headHash();
    return await objStorage.readCommit(hash);
  }

  Future<GitTree> headTree() async {
    final commit = await headCommit();
    return await objStorage.readTree(commit.treeHash);
  }

  Future<HashReference> resolveReference(Reference ref) async {
    switch (ref) {
      case HashReference():
        return ref;
      case SymbolicReference():
        final resolvedRef = await refStorage.reference(ref.target);
        if (resolvedRef == null) {
          throw GitRefNotFound(ref.target);
        }
        return resolveReference(resolvedRef);
    }
  }

  Future<HashReference?> resolveReferenceName(ReferenceName refName) async {
    var ref = await refStorage.reference(refName);
    if (ref == null) return null;
    return resolveReference(ref);
  }

  /// Converts a relative path string within the working tree to a StorageHandle.
  Future<StorageHandle> workTreeFile(String pathSpec) {
    return workTreeProvider.resolve(workTree, pathSpec);
  }

  /// Converts a StorageHandle within the working tree back to a relative path string.
  Future<String> pathSpec(StorageHandle handle) {
    return workTreeProvider.relativePath(workTree, handle);
  }

  // Example of refactoring a method that modifies state
  Future<GitHash> createBranch(
    String name, {
    GitHash? hash,
    bool overwrite = false,
  }) async {
    hash ??= await headHash();

    final branch = ReferenceName.branch(name);
    final ref = await refStorage.reference(branch);
    if (ref != null && !overwrite) {
      throw GitBranchAlreadyExists(name);
    }

    await refStorage.saveRef(HashReference(branch, hash));
    return hash;
  }

  Future<GitHash> deleteBranch(String branchName) async {
    var refName = ReferenceName.branch(branchName);
    var ref = await refStorage.reference(refName);
    if (ref == null) {
      throw GitRefNotFound(refName);
    }

    switch (ref) {
      case HashReference():
        await refStorage.deleteReference(refName);
        return ref.hash;
      case SymbolicReference():
        throw GitRefNotHash(refName);
    }
  }

  // A few more examples of async conversion
  Future<int> countTillAncestor(GitHash from, GitHash ancestor) async {
    var seen = GitHashSet();
    var parents = <GitHash>[from];
    
    while (parents.isNotEmpty) {
      var sha = parents.removeAt(0);
      if (sha == ancestor) {
        return seen.length;
      }
      if (seen.contains(sha)) continue;

      seen.add(sha);
      
      try {
        var commit = await objStorage.readCommit(sha);
        for (var p in commit.parents) {
          if (!seen.contains(p)) {
            parents.add(p);
          }
        }
      } on GitObjectNotFound {
        // Ancestor is not reachable
        return -1;
      }
    }

    return -1;
  }
}