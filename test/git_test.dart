// FILE: test/git_test.dart
import 'dart:io';

import 'package:test/test.dart';

// Change 1: Use the main library import
import 'package:dart_git/dart_git.dart';

void main() {
  test('Test can Push', () async {
    var tmpDir = (await Directory.systemTemp.createTemp('_git_')).path;

    // Change 2: 'await' the init() call
    await GitRepository.init(tmpDir);

    // Change 3: 'await' the local() factory
    var repo = await GitRepository.local(tmpDir);
    
    // Change 4: 'await' the canPush() call
    expect(await repo.canPush(), false);
  });
}