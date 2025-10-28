// lib/file_mtime_builder.dart (Corrected)

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

/// Fetches the last modification time for each file path by traversing history.
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

  @override
  Future<bool> visitTreeEntry({
    required GitCommit commit,
    required GitTree tree,
    required GitTreeEntry entry,
    required String filePath,
  }) async {
    var commitTime = commit.author.date as GDateTime;
    var changed = false;
    var info = map[filePath];

    if (info == null) {
      info = FileMTimeInfo(filePath, entry.hash, commitTime);
      changed = true;
    } else {
      // Logic to find the most recent change for a given path
      if (info.hash != entry.hash) {
        if (commitTime.isAfter(info.dt)) {
          info = FileMTimeInfo(filePath, entry.hash, commitTime);
          changed = true;
        }
      }
    }

    if (changed) {
      map[filePath] = info;
    }
    return true; // Continue traversal
  }

  GDateTime? mTime(String filePath) => map[filePath]?.dt;
  FileMTimeInfo? info(String filePath) => map[filePath];
}