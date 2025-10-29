// lib/storage/config_storage_fs.dart (Refactored)

import 'dart:convert';
import 'package:dart_git/config.dart';
import 'package:dart_git/storage/providers/storage_handle.dart';
import 'package:dart_git/storage/providers/storage_provider.dart';
import 'interfaces.dart';

class ConfigStorageFS implements ConfigStorage {
  final GitStorageProvider _provider;
  final StorageHandle _gitDirHandle;

  // This will be initialized by the factory
  final StorageHandle _configHandle;

  // Change 1: Make the constructor private
  ConfigStorageFS._(this._provider, this._gitDirHandle, this._configHandle);

  // Change 2: Create a public async factory
  static Future<ConfigStorageFS> create(
      GitStorageProvider provider, StorageHandle gitDirHandle) async {
    var configHandle = await provider.resolve(gitDirHandle, 'config');
    return ConfigStorageFS._(provider, gitDirHandle, configHandle);
  }

  @override
  Future<Config> readConfig() async {
    // Now _configHandle is guaranteed to be non-null
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