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
    var commitTime = commit.author.date as GDateTime;
    var info = map[filePath];

    if (info == null) {
      // This is the first time we've seen this file path in our newest-to-oldest
      // traversal. We provisionally set its mtime to this commit's time.
      map[filePath] = FileMTimeInfo(filePath, entry.hash, commitTime);
    } else {
      // We've seen this file path before in a newer commit.
      // If the file's content (hash) is the same as what we have stored from
      // that newer commit, it means the file was NOT changed in the newer
      // commit. Therefore, we should "walk back" the timestamp to this older
      // commit's time, as this one is a better candidate for the true
      // modification time.
      if (info.hash == entry.hash) {
        map[filePath] = FileMTimeInfo(filePath, entry.hash, commitTime);
      }
      // If the hash is different, it means the file WAS changed in the newer
      // commit, so the timestamp we already have stored is correct. We do nothing.
    }
    return true; // Continue traversal
  }

  GDateTime? mTime(String filePath) => map[filePath]?.dt;
  FileMTimeInfo? info(String filePath) => map[filePath];
}