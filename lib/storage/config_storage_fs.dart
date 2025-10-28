// lib/storage/config_storage_fs.dart (Refactored)

import 'dart:convert';
import 'package:dart_git/config.dart';
import 'package:dart_git/storage/providers/storage_handle.dart';
import 'package:dart_git/storage/providers/storage_provider.dart';
import 'interfaces.dart';

class ConfigStorageFS implements ConfigStorage {
  final GitStorageProvider _provider;
  final StorageHandle _gitDirHandle;

  late final StorageHandle _configHandle;

  ConfigStorageFS(this._provider, this._gitDirHandle) {
    // We can resolve this once since the path is constant
    _provider.resolve(_gitDirHandle, 'config').then((h) => _configHandle = h);
  }

  @override
  Future<Config> readConfig() async {
    final stream = _provider.read(_configHandle);
    final bytes = await stream.expand((b) => b).toList();
    final contents = utf8.decode(bytes);
    return Config(contents);
  }

  @override
  Future<bool> exists() => _provider.exists(_configHandle);

  @override
  Future<void> writeConfig(Config config) async {
    final data = utf8.encode(config.serialize());
    await _provider.write(_configHandle, Stream.value(data));
  }
}