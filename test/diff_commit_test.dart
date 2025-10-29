// FILE: test/diff_commit_test.dart
import 'dart:io';

import 'package:test/test.dart';

// Change 1: Simplify imports
import 'package:dart_git/dart_git.dart';
import 'lib.dart';

void main() {
  late String gitDir;

  setUp(() async {
    gitDir = (await Directory.systemTemp.createTemp()).path;
    await cloneGittedFixture('diff-commits-1', gitDir);
  });

  // Change 2: Mark the test as 'async'
  test('Duplicate Tree Object', () async {
    // Change 3: Use the async 'local' factory
    var repo = await GitRepository.local(gitDir);

    var headH = GitHash('c159d088a2336b02628053b5cc12f35caba4ad40');
    var firstH = GitHash('7abde5fb8f1773728f711d237595233c299628a3');

    // Change 4: 'await' the object reads
    var head = await repo.objStorage.readCommit(headH);
    var first = await repo.objStorage.readCommit(firstH);

    // Change 5: 'await' the diffCommits call
    var changes = await diffCommits(
      fromCommit: first,
      toCommit: head,
      objStore: repo.objStorage,
    );
    expect(changes.add.length, 2);
    expect(changes.remove.length, 0);
    expect(changes.modify.length, 0);

    var c1 = changes.add[0];
    var c2 = changes.add[1];
    expect(c1.hash, c2.hash);
    expect(c1.hash, GitHash('0cfbf08886fca9a91cb753ec8734c84fcbe52c9f'));
    expect(c1.path, isNot(c2.path));

    // Change 6: The close() method is no longer part of the public API
    // repo.close();
  });
}