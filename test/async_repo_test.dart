// FILE: test/async_repo_test.dart
import 'dart:io';

import 'package:test/test.dart';

import 'package:dart_git/dart_git.dart';
import 'package:dart_git/exceptions.dart';
import 'package:dart_git/plumbing/git_hash.dart';

import 'lib.dart';

void main() {
  late String gitDir;

  setUp(() async {
    gitDir = (await Directory.systemTemp.createTemp('_git_')).path;
    await cloneGittedFixture('mtime', gitDir);
  });

  test('Basic', () async {
    // Change 1: Use the main GitRepository.local() factory instead of GitAsyncRepository.load()
    var repo = await GitRepository.local(gitDir);

    expect(await repo.currentBranch(), "master");
    expect(await repo.branches(), ["master"]);
    expect(await repo.headHash(),
        GitHash('386de870a014e32234ce7f87e59a1beb06f720df'));

    // Change 2: Assert a more specific exception type for better testing.
    await expectLater(() async {
      await repo.deleteBranch('non-existent-branch');
    }, throwsA(isA<GitRefNotFound>()));

    // Change 3: The close() method is no longer part of the public GitRepository API.
    // repo.close();
  });
}