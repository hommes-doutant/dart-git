// FILE: test/commit_test.dart
import 'dart:io';

import 'package:test/test.dart';

// Change 1: Simplify imports
import 'package:dart_git/dart_git.dart';
import 'lib.dart';

void main() {
  test(
    'fixture mtime',
    // Change 2: Mark the test body async
    () async => testFixture(
      'mtime',
      '386de870a014e32234ce7f87e59a1beb06f720df',
      '21d0abfb760ab8d62d293ff5a0e8ad87729d220b',
    ),
  );

  test(
    'fixture merge',
    () async => testFixture(
      'merge',
      'd377980616840997f6450f79c7b5f9701cf30ca3',
      'd1fd63822c1497e93bae52d2b65acbb613c573ac',
    ),
  );
}

// Change 3: Mark the helper function as async and return a Future
Future<void> testFixture(String name, String headHash, String treeHash) async {
  var gitDir = Directory.systemTemp.createTempSync('_git_').path;
  await cloneGittedFixture(name, gitDir, GitHash(headHash));

  // Change 4: Use the async 'local' factory
  var repo = await GitRepository.local(gitDir);
  
  // Change 5: 'await' the readIndex and writeTree calls
  var index = await repo.indexStorage.readIndex();
  var treeH = await repo.writeTree(index);
  
  expect(treeH, GitHash(treeHash));

  // Change 6: The close() method is no longer part of the public API
  // repo.close();
}