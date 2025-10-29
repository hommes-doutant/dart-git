// lib/storage/interfaces.dart (Updated)

import 'package:dart_git/config.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/index.dart';
import 'package:dart_git/plumbing/objects/object.dart';
import 'package:dart_git/plumbing/reference.dart';

export 'object_storage_extensions.dart';

abstract class ConfigStorage {
  Future<Config> readConfig();
  Future<bool> exists();
  Future<void> writeConfig(Config config);
}

abstract class ReferenceStorage {
  Future<Reference?> reference(ReferenceName refName);
  Future<List<Reference>> listReferences(String prefix);
  Future<void> saveRef(Reference ref);
  Future<void> removeReferences(String prefix);
  Future<void> deleteReference(ReferenceName refName);
  Future<void> close();
}

abstract class ObjectStorage {
  Future<GitObject> read(GitHash hash);
  Future<GitHash> writeObject(GitObject obj);
  Future<void> close();
}

abstract class IndexStorage {
  Future<GitIndex> readIndex();
  Future<void> writeIndex(GitIndex index);
  Future<void> close();
}