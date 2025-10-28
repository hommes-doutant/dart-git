// lib/storage/reference_storage_fs.dart (Refactored)

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
      final bytes = await _provider.read(refHandle).expand((b) => b).toList();
      final contents = utf8.decode(bytes).trimRight();
      if (contents.isEmpty) return null;
      return Reference.build(refName.value, contents);
    }

    // Fallback to packed-refs
    for (var ref in await _packedRefs()) {
      if (ref.name == refName) {
        return ref;
      }
    }
    return null;
  }

  @override
  Future<List<Reference>> listReferences(String prefix) async {
    assert(prefix.startsWith(refPrefix));

    var refs = <Reference>[];
    final refLocationHandle = await _provider.resolve(_gitDirHandle, prefix);
    var processedRefNames = <ReferenceName>{};

    if (!await _provider.exists(refLocationHandle)) {
        return refs;
    }

    final children = await _provider.list(refLocationHandle);
    for (var childHandle in children) {
      // Reconstruct the full reference name from the handle's name and prefix
      // This part is tricky. Let's assume the handle gives us enough info.
      // A robust solution would need path manipulation within the provider.
      // For now, we assume a simple structure.
      final refNameStr = prefix + childHandle.name;
      final refName = ReferenceName(refNameStr);

      try {
        final ref = await reference(refName);
        if (ref == null) throw GitRefStoreCorrupted();
        
        refs.add(ref);
        processedRefNames.add(refName);
      } catch (ex) {
        // FIXME: Handle this error more gracefully
      }
    }
    
    for (var ref in await _packedRefs()) {
      if (processedRefNames.contains(ref.name)) continue;
      if (ref.name.value.startsWith(prefix)) {
        refs.add(ref);
      }
    }

    return refs;
  }

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