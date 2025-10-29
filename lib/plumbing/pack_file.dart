// lib/plumbing/pack_file.dart (Refactored)

import 'dart:async';
import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:typed_data';

import 'package:buffer/buffer.dart';
import 'package:dart_git/exceptions.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/idx_file.dart';
import 'package:dart_git/plumbing/objects/object.dart';
import 'package:dart_git/plumbing/pack_file_delta.dart';
import 'package:dart_git/storage/providers/storage_handle.dart';
import 'package:dart_git/storage/providers/storage_provider.dart';
import 'package:dart_git/utils/bytes_data_reader.dart';

class PackFile {
  final IdxFile idx;
  final int numObjects;
  final GitStorageProvider _provider;
  final StorageHandle _handle;

  // Private constructor, initialization is done via the async factory.
  PackFile._({
    required this.idx,
    required this.numObjects,
    required GitStorageProvider provider,
    required StorageHandle handle,
  })  : _provider = provider,
        _handle = handle;

  /// Asynchronously creates and initializes a PackFile from storage.
  static Future<PackFile> fromStorage({
    required IdxFile idx,
    required GitStorageProvider provider,
    required StorageHandle handle,
  }) async {
    // Read and validate the 12-byte header.
    final headerBytes = await provider.readRange(handle, 0, 12);
    final reader = ByteDataReader(endian: Endian.big)..add(headerBytes);

    final sigBytes = reader.read(4);
    if (utf8.decode(sigBytes) != 'PACK') {
      throw Exception('GitPackFileCorrupted: Invalid signature');
    }

    final version = reader.readUint32();
    if (version != 2) {
      throw Exception('GitPackFileCorrupted: Unsupported version: $version');
    }

    final numObjects = reader.readUint32();

    return PackFile._(
      idx: idx,
      numObjects: numObjects,
      provider: provider,
      handle: handle,
    );
  }

  Future<GitObject?> object(GitHash hash) async {
    final rawObj = await _rawObjectByHash(hash);
    if (rawObj == null) return null;
    return createObject(rawObj.type, rawObj.data, hash);
  }

  Future<RawObject?> _rawObjectByHash(GitHash hash) async {
    final entry = idx.entry(hash);
    if (entry == null) return null;
    return _rawObjectByOffset(entry.offset);
  }

  Future<RawObject?> _rawObjectByOffset(int offset) async {
    final reader = _PackFileReader(_provider, _handle, offset);

    // Read object header
    final headByte = await reader.readByte();
    final type = (0x70 & headByte) >> 4;
    var size = headByte & 0x0f;
    var needMore = (0x80 & headByte) > 0;
    var bitsToShift = 4;

    while (needMore) {
      final byte = await reader.readByte();
      needMore = (0x80 & byte) > 0;
      size |= (byte & 0x7f) << bitsToShift;
      bitsToShift += 7;
    }

    // Handle delta objects
    switch (type) {
      case ObjectTypes.OFS_DELTA:
        final n = await reader.readVariableWidthInt();
        final baseOffset = offset - n;
        final deltaData = await _readZlibObject(reader);
        return _inflateOFSDelta(baseOffset, deltaData);

      case ObjectTypes.REF_DELTA:
        final hashBytes = await reader.read(20);
        final hash = GitHash.fromBytes(hashBytes);
        final deltaData = await _readZlibObject(reader);
        return _inflateRefDelta(hash, deltaData);

      default:
        final rawData = await _readZlibObject(reader);
        if (rawData.length != size) {
          throw Exception('Packfile object size mismatch');
        }
        return RawObject(data: rawData, type: type);
    }
  }

  Future<Uint8List> _readZlibObject(_PackFileReader reader) async {
    // This is still tricky as zlib is stream-based. We read a reasonable
    // amount of data, assuming the compressed object is smaller than the chunk.
    // For huge objects, this might need a more sophisticated streaming inflater.
    final compressedData = await reader.readToEnd();
    return zlib.decode(compressedData) as Uint8List;
  }

  Future<RawObject?> _inflateOFSDelta(int baseOffset, Uint8List deltaData) async {
    final baseObject = await _rawObjectByOffset(baseOffset);
    if (baseObject == null) return null;

    final patchedData = patchDelta(baseObject.data, deltaData);
    return RawObject(data: patchedData, type: baseObject.type);
  }

  Future<RawObject?> _inflateRefDelta(GitHash baseHash, Uint8List deltaData) async {
    final baseObject = await _rawObjectByHash(baseHash);
    if (baseObject == null) return null;

    final patchedData = patchDelta(baseObject.data, deltaData);
    return RawObject(data: patchedData, type: baseObject.type);
  }
}

/// A helper class to provide buffered random-access reading on top of the
/// stateless `GitStorageProvider`.
class _PackFileReader {
  final GitStorageProvider _provider;
  final StorageHandle _handle;
  int _fileOffset;

  Uint8List _buffer = Uint8List(0);
  int _bufferOffset = 0;

  static const int _bufferSize = 8192; // 8KB buffer

  _PackFileReader(this._provider, this._handle, this._fileOffset);

  Future<void> _fillBuffer() async {
    _buffer = await _provider.readRange(_handle, _fileOffset, _fileOffset + _bufferSize);
    _bufferOffset = 0;
  }

  Future<int> readByte() async {
    final bytes = await read(1);
    return bytes[0];
  }

  Future<Uint8List> read(int bytesToRead) async {
    if (_bufferOffset + bytesToRead <= _buffer.length) {
      final result = _buffer.sublist(_bufferOffset, _bufferOffset + bytesToRead);
      _bufferOffset += bytesToRead;
      _fileOffset += bytesToRead;
      return result;
    }

    // If the request spans beyond the buffer, fall back to a direct read.
    // A more complex implementation could handle this with buffer stitching.
    final result = await _provider.readRange(_handle, _fileOffset, _fileOffset + bytesToRead);
    _fileOffset += bytesToRead;
    // Invalidate the buffer as it's now out of sync
    _buffer = Uint8List(0);
    _bufferOffset = 0;
    return result;
  }

  Future<int> readVariableWidthInt() async {
    // Read the first byte to start
    var byte = await readByte();
    var value = byte & 0x7f;

    while ((byte & 0x80) != 0) {
      value++;
      byte = await readByte();
      value = (value << 7) | (byte & 0x7f);
    }
    return value;
  }
  
  Future<Uint8List> readToEnd() async {
    // This is an approximation. We assume we want the rest of the file from the current position.
    // In a real packfile stream, the end is not known. We read a large chunk.
    final stat = await _provider.stat(_handle);
    return read(stat.size - _fileOffset);
  }
}

// Ensure RawObject is still available. It's a simple data class.
class RawObject {
  final Uint8List data;
  final int type;
  RawObject({required this.data, required this.type});
}