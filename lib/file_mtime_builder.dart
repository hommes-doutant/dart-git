// FILE: lib/file_mtime_builder.dart (FINAL, CORRECTED VERSION)

import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/tree.dart';
import 'package:dart_git/utils/date_time.dart';
import 'package:dart_git/utils/git_hash_set.dart';

class FileMTimeInfo {
  String filePath;
  GitHash hash;
  GDateTime dt;

  FileMTimeInfo(this.filePath, this.hash, this.dt);

  @override
  String toString() {
    return 'FileMtimeInfo{filePath: $filePath, hash: $hash, dt: $dt}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileMTimeInfo &&
          filePath == other.filePath &&
          hash == other.hash &&
          dt == other.dt;

  @override
  int get hashCode => Object.hashAll([filePath, hash, dt]);
}

class FileMTimeBuilder extends TreeEntryVisitor {
  var processedCommits = GitHashSet();
  var map = <String, FileMTimeInfo>{};

  FileMTimeBuilder({
    Set<GitHash>? processedCommits,
    Map<String, FileMTimeInfo>? map,
  }) : map = map ?? {} {
    this.processedCommits = GitHashSet.from(processedCommits);
  }

  void update(FileMTimeBuilder b) {
    processedCommits = b.processedCommits;
    map = b.map;
  }

  @override
  Future<bool> beforeCommit(GitHash commitHash) async {
    return !processedCommits.contains(commitHash);
  }

  @override
  Future<void> afterCommit(GitCommit commit) async {
    processedCommits.add(commit.hash);
  }
  
  // This is the corrected logic
  @override
  Future<bool> visitTreeEntry({
    required GitCommit commit,
    required GitTree tree,
    required GitTreeEntry entry,
    required String filePath,
  }) async {
    var previousInfo = map[filePath];
    var commitTime = commit.author.date as GDateTime;

    if (previousInfo == null) {
      // First time we see this path. Record its state. The timestamp is a candidate.
      map[filePath] = FileMTimeInfo(filePath, entry.hash, commitTime);
    } else if (previousInfo.hash != entry.hash) {
      // The hash has changed! This means the file was modified in the *newer*
      // commit we came from. The timestamp stored in `previousInfo` is the correct
      // modification time. We must preserve it.
      // We update the hash to this older commit's hash to detect the next change,
      // but we keep the newer timestamp.
      map[filePath] = FileMTimeInfo(filePath, entry.hash, previousInfo.dt);
    }
    // If hashes are the same, do nothing. The timestamp candidate from the newer
    // commit is still valid.

    return true; // Continue traversal
  }

  GDateTime? mTime(String filePath) => map[filePath]?.dt;
  FileMTimeInfo? info(String filePath) => map[filePath];
}