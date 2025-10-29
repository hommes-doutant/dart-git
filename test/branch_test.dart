// FILE: test/branch_test.dart
import 'dart:io';

import 'package:test/test.dart';

import 'package:dart_git/dart_git.dart';
import 'lib.dart';

void main() {
  late String gitDir;

  setUp(() async {
    gitDir = (await Directory.systemTemp.createTemp('_git_')).path;
    await cloneGittedFixture('mtime', gitDir);
  });

  // Change 1: Mark the test as 'async'
  test('Branch with a /', () async {
    // Change 2: Use the async 'local' factory
    var repo = await GitRepository.local(gitDir);
    
    // Change 3: 'await' the result of currentBranch()
    expect(await repo.currentBranch(), "master");

    // Change 4: 'await' the createBranch() call
    await repo.createBranch('hello/there');
    
    // Change 5: 'await' the result of branches()
    // The parentheses are important to ensure 'await' completes before '.sort()' is called
    expect((await repo.branches())..sort(), ["hello/there", "master"]);

    // Change 6: The close() method is no longer part of the public API
    // repo.close();
  });
}