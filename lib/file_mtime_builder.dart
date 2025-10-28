// FILE: lib/file_mtime_builder.dart
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

  // Change 1: Make method return a Future<bool>
  @override
  Future<bool> beforeCommit(GitHash commitHash) async {
    return !processedCommits.contains(commitHash);
  }

  // Change 2: Make method return a Future<void>
  @override
  Future<void> afterCommit(GitCommit commit) async {
    processedCommits.add(commit.hash);
  }

  // Change 3: Make method return a Future<bool> and implement the correct logic
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
      // This is the restored, correct logic
      if (info.hash == entry.hash) {
        // Same content hash, looking for the earliest appearance (creation).
        // Git history traversal is typically newest to oldest, so we
        // are effectively looking for the "oldest" time we've seen for this hash.
        if (commitTime.isBefore(info.dt)) {
          info = FileMTimeInfo(filePath, entry.hash, commitTime);
          changed = true;
        }
      } else {
        // Different content hash, this is a modification.
        // We want the latest time for this modification.
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