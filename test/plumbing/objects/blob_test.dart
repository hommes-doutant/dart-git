// FILE: test/plumbing/objects/blob_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:test/test.dart';

// Change 1: Update imports to use the main library and providers
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/storage/object_storage_fs.dart';
import 'package:dart_git/storage/providers/path_based_storage_provider.dart';

void main() {
  // Change 2: Mark test as async
  test('Reads the blob file correctly', () async {
    const fs = LocalFileSystem();
    var fp = 'test/data/blob';
    expect(File(fp).existsSync(), equals(true));

    // Change 3: Set up the provider and handle
    final provider = PathBasedStorageProvider(fs);
    final gitDirHandle = PathBasedStorageHandle('.'); // Dummy handle for constructor
    final blobFileHandle = PathBasedStorageHandle(fp);

    // Change 4: Instantiate ObjectStorageFS with the new provider
    var objStorage = ObjectStorageFS(provider, gitDirHandle);

    var data = File(fp).readAsBytesSync();
    var hash = GitHash.compute(GitObject.envelope(
      data: data,
      format: ascii.encode(GitBlob.fmt),
    ));

    // Change 5: Use the new async method with the handle
    var obj = await objStorage.readObjectFromHandle(blobFileHandle, hash);

    expect(obj is GitBlob, equals(true));
    var blob = obj as GitBlob; // Cast for clarity and type safety
    expect(blob.serializeData(), equals(ascii.encode('FOO\n')));

    var fileRawBytes = await File('test/data/blob').readAsBytes();
    var fileBytesDeflated = zlib.decode(fileRawBytes);
    expect(
      GitObject.envelope(data: blob.serializeData(), format: blob.format()),
      equals(fileBytesDeflated),
    );
  });
}