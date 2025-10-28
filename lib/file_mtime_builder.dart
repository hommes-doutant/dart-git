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

  @override
  Future<bool> beforeCommit(GitHash commitHash) async {
    return !processedCommits.contains(commitHash);
  }

  @override
  Future<void> afterCommit(GitCommit commit) async {
    processedCommits.add(commit.hash);
  }

  // Change 1: Replace the entire method body with corrected logic
  @override
  Future<bool> visitTreeEntry({
    required GitCommit commit,
    required GitTree tree,
    required GitTreeEntry entry,
    required String filePath,
  }) async {
    var previousInfo = map[filePath];

    // If we have never seen this path before, this commit is our first candidate for its mtime.
    // Or, if we have seen this path before but its hash is different in this older commit,
    // it means the file was changed in the *newer* commit we saw previously.
    // In that case, the timestamp we already have in the map (`previousInfo.dt`) is the correct mtime,
    // and we should "lock it in" by updating the hash to prevent further changes.
    if (previousInfo == null) {
      // First time we encounter this path. Record the current state.
      map[filePath] = FileMTimeInfo(filePath, entry.hash, commit.author.date as GDateTime);
    } else if (previousInfo.hash != entry.hash) {
      // The hash has changed from a newer commit to this older one. This means
      // the modification happened at the time of the newer commit. The time currently
      // in the map is correct. We now update the hash in our map to reflect the
      // state in this older commit, so we can detect the next change as we go further back.
      map[filePath] = FileMTimeInfo(filePath, entry.hash, commit.author.date as GDateTime);
    }
    
    return true; // Continue traversal
  }

  GDateTime? mTime(String filePath) => map[filePath]?.dt;
  FileMTimeInfo? info(String filePath) => map[filePath];
}