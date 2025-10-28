// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:async/async.dart' show NullStreamSink;
import 'package:path/path.dart' as p;
import 'package:process_run/process_run.dart';
import 'package:process_run/shell.dart' as shell;
import 'package:test/test.dart';

import 'package:dart_git/config.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/commit.dart';

import 'package:dart_git/dart_git.dart';


var inCI = Platform.environment["CI"] != null;
var silenceShellOutput = !inCI;

void createFile(String basePath, String path, String contents) {
  var fullPath = p.join(basePath, path);

  Directory(p.dirname(fullPath)).createSync(recursive: true);
  File(fullPath).writeAsStringSync(contents);
}

Future<void> copyDirectory(String source, String destination) async {
  await Directory(destination).create(recursive: true);
  await for (var entity in Directory(source).list(recursive: false)) {
    if (entity is Directory) {
      var newDirectory = Directory(p.join(
          Directory(destination).absolute.path, p.basename(entity.path)));
      await newDirectory.create();
      await copyDirectory(entity.absolute.path, newDirectory.path);
    } else if (entity is File) {
      await entity.copy(p.join(destination, p.basename(entity.path)));
    }
  }
}

Future<String> openFixture(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  final gzipBytes = GZipDecoder().decodeBytes(bytes);
  final archive = TarDecoder().decodeBytes(gzipBytes);

  var gitDir = (await Directory.systemTemp.createTemp()).path;
  var gitDotDir = p.join(gitDir, '.git');

  for (var file in archive) {
    var filename = file.name;
    if (file.isFile) {
      var data = file.content as List<int>;
      File(p.join(gitDotDir, filename))
        ..createSync(recursive: true)
        ..writeAsBytesSync(data);
    } else {
      await Directory(p.join(gitDotDir, filename)).create(recursive: true);
    }
  }

  return gitDir;
}

Future<String> cloneGittedFixture(String fixtureName, String newDirPath,
    [GitHash? hash]) async {
  var fixtureDirPath = 'test/data/$fixtureName';
  assert(Directory(fixtureDirPath).existsSync());
  assert(Directory('$fixtureDirPath/.gitted').existsSync());

  await copyDirectory(fixtureDirPath, newDirPath);
  assert(Directory('$newDirPath/.gitted').existsSync());
  await Directory('$newDirPath/.gitted').rename('$newDirPath/.git');

  await shell.run(
    'git reset HEAD .',
    workingDirectory: newDirPath,
    includeParentEnvironment: false,
    verbose: false,
  );

  if (hash != null) {
    await shell.run(
      'git checkout $hash',
      workingDirectory: newDirPath,
      includeParentEnvironment: false,
      verbose: false,
    );
  }

  return newDirPath;
}

extension GitCommitStreamExtensions on Stream<GitCommit> {
  Future<List<String>> asHashStrings() async {
    var list = <String>[];
    // Change 4: Use 'await for' to correctly consume the stream
    await for (var commit in this) {
      var hash = commit.hash.toString();
      list.add(hash);
    }
    return list;
  }
}
