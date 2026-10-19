import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'kurotoon_database.dart';

/// A rejected cache write never evicts existing content.
class CacheWriteRejected implements Exception {
  const CacheWriteRejected(this.reason);

  final String reason;

  @override
  String toString() => 'CacheWriteRejected: $reason';
}

/// Filesystem-backed cache with budget planning, serialized writes, and a
/// rollback path if either a rename or the SQLite metadata transaction fails.
///
/// This service only manages disposable cache bytes. It must never be used for
/// library records, reading progress, repository manifests, or user exports.
class CacheStorageService {
  CacheStorageService._({
    required this.database,
    required this.budget,
    required Directory rootDirectory,
  }) : _rootDirectory = rootDirectory;

  static Future<CacheStorageService> create({
    required KurotoonDatabase database,
    required StorageBudget budget,
    Directory? rootDirectory,
  }) async {
    final root = rootDirectory ??
        Directory(path.join((await getTemporaryDirectory()).path, 'kurotoon-cache'));
    await root.create(recursive: true);
    return CacheStorageService._(
      database: database,
      budget: budget,
      rootDirectory: root,
    );
  }

  final KurotoonDatabase database;
  final StorageBudget budget;
  final Directory _rootDirectory;
  Future<void> _writeQueue = Future<void>.value();
  bool _disposed = false;

  Directory get rootDirectory => _rootDirectory;

  /// Writes bytes only if the budget can accommodate them without evicting
  /// pinned entries. Evicted files are staged as same-directory backups until
  /// SQLite commits the replacement metadata.
  Future<CacheEntryFile> writeBytes({
    required String key,
    required CacheBucket bucket,
    required List<int> bytes,
    bool pinned = false,
  }) {
    if (_disposed) throw StateError('Cache storage service is disposed.');
    if (key.trim().isEmpty) throw ArgumentError.value(key, 'key', 'Cache key cannot be empty.');
    return _enqueue(() => _writeBytes(
          key: key,
          bucket: bucket,
          bytes: List<int>.unmodifiable(bytes),
          pinned: pinned,
        ));
  }

  Future<CacheEntryFile> _writeBytes({
    required String key,
    required CacheBucket bucket,
    required List<int> bytes,
    required bool pinned,
  }) async {
    final existing = await database.findCacheEntry(key);
    final preservedPin = pinned || (existing?.entry.pinned ?? false);
    final digest = sha256.convert(utf8.encode(key)).toString();
    final target = File(path.join(_rootDirectory.path, bucket.name, digest + '.bin'));
    await target.parent.create(recursive: true);

    final plan = await database.planCacheWrite(
      incomingBytes: bytes.length,
      budget: budget,
      replacingKey: key,
    );
    if (!plan.storagePlan.accepted) {
      throw CacheWriteRejected(plan.storagePlan.reason);
    }

    final allEntries = await database.loadCacheEntries();
    final evictedKeys = plan.storagePlan.evictKeys.toSet();
    final evictedEntries = allEntries.where((entry) => evictedKeys.contains(entry.entry.key)).toList();
    final pathsToStage = <String>{...evictedEntries.map((entry) => entry.filePath)};
    if (existing != null && existing.filePath != target.path) {
      pathsToStage.add(existing.filePath);
    }
    for (final filePath in pathsToStage) {
      if (!_isManagedPath(filePath)) {
        throw StateError('Refusing to evict a cache path outside the managed cache directory.');
      }
    }

    final nonce = DateTime.now().microsecondsSinceEpoch;
    final temporary = File(target.path + '.pending-' + nonce.toString());
    final backups = <String, String>{};
    var targetInstalled = false;
    var metadataCommitted = false;

    try {
      await temporary.writeAsBytes(bytes, flush: true);

      for (final originalPath in pathsToStage) {
        final original = File(originalPath);
        if (!await original.exists()) continue;
        final backupPath = originalPath + '.rollback-' + nonce.toString();
        await original.rename(backupPath);
        backups[originalPath] = backupPath;
      }

      // If the target path belongs to an older cache key, it is not allowed
      // to be overwritten without staging it first.
      if (await target.exists() && !backups.containsKey(target.path)) {
        final backupPath = target.path + '.rollback-' + nonce.toString();
        await target.rename(backupPath);
        backups[target.path] = backupPath;
      }

      await temporary.rename(target.path);
      targetInstalled = true;

      final entry = CacheEntryFile(
        entry: CacheEntry(
          key: key,
          bucket: bucket,
          bytes: bytes.length,
          lastAccessedAt: DateTime.now(),
          pinned: preservedPin,
        ),
        filePath: target.path,
      );
      await database.commitCacheWrite(entry, evictedKeys: evictedKeys);
      metadataCommitted = true;

      // A backup left behind by a filesystem permission error is an orphan,
      // not a reason to roll back an already committed cache index.
      for (final backupPath in backups.values) {
        try {
          final backup = File(backupPath);
          if (await backup.exists()) await backup.delete();
        } on Object {
          // A future maintenance pass may clean this disposable orphan.
        }
      }
      return entry;
    } catch (_) {
      if (metadataCommitted) rethrow;
      if (targetInstalled && await target.exists()) {
        try {
          await target.delete();
        } on FileSystemException {
          // Preserve the original failure; the staged backup remains available.
        }
      }
      for (final backup in backups.entries.toList().reversed) {
        try {
          final backupFile = File(backup.value);
          if (await backupFile.exists()) {
            final original = File(backup.key);
            await original.parent.create(recursive: true);
            if (await original.exists()) await original.delete();
            await backupFile.rename(original.path);
          }
        } on FileSystemException {
          // Preserve the original failure and leave the rollback file recoverable.
        }
      }
      rethrow;
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } on FileSystemException {
          // Temporary files are disposable and can be cleaned later.
        }
      }
    }
  }

  /// Removes a cache file and its index record as one recoverable operation.
  Future<void> remove(String key) {
    if (_disposed) throw StateError('Cache storage service is disposed.');
    return _enqueue(() async {
      final entry = await database.findCacheEntry(key);
      if (entry == null) return;
      if (!_isManagedPath(entry.filePath)) {
        throw StateError('Refusing to remove a cache path outside the managed cache directory.');
      }
      final original = File(entry.filePath);
      final nonce = DateTime.now().microsecondsSinceEpoch;
      final backup = File(entry.filePath + '.remove-' + nonce.toString());
      var staged = false;
      try {
        if (await original.exists()) {
          await original.rename(backup.path);
          staged = true;
        }
        await database.confirmCacheEviction([key]);
        if (staged && await backup.exists()) await backup.delete();
      } catch (_) {
        if (staged && await backup.exists()) {
          if (await original.exists()) await original.delete();
          await backup.rename(original.path);
        }
        rethrow;
      }
    });
  }

  bool _isManagedPath(String candidate) {
    final root = path.normalize(path.absolute(_rootDirectory.path));
    final file = path.normalize(path.absolute(candidate));
    return path.isWithin(root, file);
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _writeQueue;
  }
}
