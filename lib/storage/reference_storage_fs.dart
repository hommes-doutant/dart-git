// FILE: lib/storage/reference_storage_fs.dart
import 'dart:convert';
import 'package:dart_git/exceptions.dart';
import 'package:dart_git/plumbing/reference.dart';
import 'package:dart_git/storage/providers/storage_handle.dart';
import 'package:dart_git/storage/providers/storage_provider.dart';
import 'interfaces.dart';

class ReferenceStorageFS implements ReferenceStorage {
  final GitStorageProvider _provider;
  final StorageHandle _gitDirHandle;

  ReferenceStorageFS(this._provider, this._gitDirHandle);

  @override
  Future<Reference?> reference(ReferenceName refName) async {
    final refHandle = await _provider.resolve(_gitDirHandle, refName.value);
    if (await _provider.exists(refHandle)) {
      final stat = await _provider.stat(refHandle);
      if (stat.type == StorageEntryType.directory) {
        // This can happen if a branch like 'foo' exists and we look for 'foo/bar'
        return null; 
      }
      final bytes = await _provider.read(refHandle).expand((b) => b).toList();
      final contents = utf8.decode(bytes).trimRight();
      if (contents.isEmpty) return null;
      return Reference.build(refName.value, contents);
    }

    // Fallback to packed-refs
    for (var ref in await _packedRefs()) {
      if (ref.name.value == refName.value) { // Compare by value for correctness
        return ref;
      }
    }
    return null;
  }

  @override
  Future<List<Reference>> listReferences(String prefix) async {
    assert(prefix.startsWith(refPrefix));

    var refs = <Reference>[];
    var processedRefNames = <String>{};

    // Change 1: Create a recursive helper function to traverse directories
    Future<void> collectRefs(StorageHandle dirHandle, String currentPrefix) async {
      if (!await _provider.exists(dirHandle)) return;
      
      final children = await _provider.list(dirHandle);
      for (final childHandle in children) {
        final stat = await _provider.stat(childHandle);
        final newPrefix = '$currentPrefix${childHandle.name}';
        
        if (stat.type == StorageEntryType.directory) {
          // If it's a directory, recurse into it
          await collectRefs(childHandle, '$newPrefix/');
        } else {
          // If it's a file, it's a reference
          try {
            final refName = ReferenceName(newPrefix);
            final ref = await reference(refName);
            if (ref == null) throw GitRefStoreCorrupted();
            
            refs.add(ref);
            processedRefNames.add(refName.value);
          } catch (ex) {
            // FIXME: Handle this error more gracefully
          }
        }
      }
    }
    
    // Change 2: Start the recursive collection
    final refLocationHandle = await _provider.resolve(_gitDirHandle, prefix);
    await collectRefs(refLocationHandle, prefix);
    
    for (var ref in await _packedRefs()) {
      if (processedRefNames.contains(ref.name.value)) continue;
      if (ref.name.value.startsWith(prefix)) {
        refs.add(ref);
      }
    }

    return refs;
  }

  // ... (rest of the file remains the same) ...
  @override
  Future<void> removeReferences(String prefix) async {
    assert(prefix.startsWith(refPrefix));
    final refLocationHandle = await _provider.resolve(_gitDirHandle, prefix);
    if (await _provider.exists(refLocationHandle)) {
      await _provider.delete(refLocationHandle, recursive: true);
    }
  }

  @override
  Future<void> saveRef(Reference ref) async {
    final refHandle = await _provider.resolve(_gitDirHandle, ref.name.value);
    final data = utf8.encode(ref.serialize());
    await _provider.write(refHandle, Stream.value(data));
  }
  
  @override
  Future<void> deleteReference(ReferenceName refName) async {
    final refHandle = await _provider.resolve(_gitDirHandle, refName.value);
    if (await _provider.exists(refHandle)) {
      await _provider.delete(refHandle);
    }
  }

  Future<List<Reference>> _packedRefs() async {
    final packedRefsHandle = await _provider.resolve(_gitDirHandle, 'packed-refs');
    if (!await _provider.exists(packedRefsHandle)) {
      return [];
    }
    final bytes = await _provider.read(packedRefsHandle).expand((b) => b).toList();
    final contents = utf8.decode(bytes);
    return _loadPackedRefs(contents);
  }

  List<Reference> _loadPackedRefs(String raw) {
    var refs = <Reference>[];
    for (var line in LineSplitter.split(raw)) {
      if (line.startsWith('#') || line.startsWith('^')) continue;
      var parts = line.split(' ');
      if (parts.length != 2) continue;
      refs.add(Reference.build(parts[1], parts[0]));
    }
    return refs;
  }

  @override
  Future<void> close() async {
    // No-op for this implementation, but required by the interface.
  }
}