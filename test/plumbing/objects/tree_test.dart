// FILE: test/plumbing/objects/tree_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:test/test.dart';

// Change 1: Update imports
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/storage/object_storage_fs.dart';
import 'package:dart_git/storage/providers/path_based_storage_provider.dart';

void main() {
  // Change 2: Mark test as async
  test('Reads the tree file correctly', () async {
    const fs = LocalFileSystem();

    var fp = 'test/data/tree';
    expect(File(fp).existsSync(), equals(true));

    // Change 3: Set up provider and handles
    final provider = PathBasedStorageProvider(fs);
    final gitDirHandle = PathBasedStorageHandle('.'); // Dummy handle
    final treeFileHandle = PathBasedStorageHandle(fp);

    // Change 4: Instantiate ObjectStorageFS with provider
    var objStorage = ObjectStorageFS(provider, gitDirHandle);

    var data = File(fp).readAsBytesSync();
    var hash = GitHash.compute(GitObject.envelope(
      data: data,
      format: ascii.encode(GitTree.fmt),
    ));

    // Change 5: Use the new async method with the handle
    var obj = await objStorage.readObjectFromHandle(treeFileHandle, hash);
    expect(obj is GitTree, equals(true));

    var tree = obj as GitTree;
    expect(tree.entries.length, 2);

    var leaf0 = tree.entries[0];
    expect(leaf0.mode.toString(), '100644');
    expect(leaf0.hash.toString(), '43fcaffe80f693d06f3c309e354bdbff5d6baa43');
    expect(leaf0.name, 'c.md');

    var leaf1 = tree.entries[1];
    expect(leaf1.mode.toString(), '100644');
    expect(leaf1.hash.toString(), '61f69766977e3d234e15bd1a58c01aa697039439');
    expect(leaf1.name, 'd.md');

    var fileRawBytes = await fs.file('test/data/tree').readAsBytes();
    var fileBytesDefalted = zlib.decode(fileRawBytes);
    expect(
        GitObject.envelope(data: tree.serializeData(), format: tree.format()),
        equals(fileBytesDefalted));
  });
}