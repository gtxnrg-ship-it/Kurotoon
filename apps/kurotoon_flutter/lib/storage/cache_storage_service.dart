import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'kurotoon_database.dart';

/// A rejected cache write never evicts existing content.
class CacheRecoveryReport {
  const CacheRecoveryReport({
    this.operationsRecovered = 0,
    this.pendingFilesRemoved = 0,
    this.orphanBackupsHandled = 0,
    this.orphanFilesRemoved = 0,
    this.failures = 0,
  });

  final int operationsRecovered;
  final int pendingFilesRemoved;
  final int orphanBackupsHandled;
  final int orphanFilesRemoved;
  final int failures;

  bool get changed => operationsRecovered + pendingFilesRemoved + orphanBackupsHandled + orphanFilesRemoved > 0;
  bool get complete => failures == 0;
}

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
    final service = CacheStorageService._(
      database: database,
      budget: budget,
      rootDirectory: root,
    );
    // Repairs interrupted rename/metadata operations before cache reads begin.
    await service.recoverInterruptedOperations();
    return service;
  }

  final KurotoonDatabase database;
  final StorageBudget budget;
  final Directory _rootDirectory;
  Future<void> _writeQueue = Future<void>.value();
  bool _disposed = false;
  CacheRecoveryReport _lastRecoveryReport = const CacheRecoveryReport();

  Directory get rootDirectory => _rootDirectory;
  CacheRecoveryReport get lastRecoveryReport => _lastRecoveryReport;

  /// Replays interrupted filesystem operations and cleans unindexed temporary
  /// artifacts. An operation journal is removed only after rollback completes,
  /// or atomically together with a committed metadata transaction.
  Future<CacheRecoveryReport> recoverInterruptedOperations() {
    if (_disposed) throw StateError('Cache storage service is disposed.');
    return _enqueue(() async {
      var recovered = 0;
      var failures = 0;
      var pendingRemoved = 0;
      var orphanBackupsHandled = 0;
      var orphanFilesRemoved = 0;

      final journals = await database.loadCacheOperationJournals();
      for (final journal in journals) {
        try {
          final success = await _recoverJournal(journal);
          if (!success) {
            failures++;
            continue;
          }
          await database.removeCacheOperationJournal(journal.id);
          recovered++;
        } on Object {
          // Keep failed records intact for the next startup; cache maintenance
          // should not block the user's library or reader.
          failures++;
        }
      }

      final remaining = await database.loadCacheOperationJournals();
      if (remaining.isEmpty) {
        try {
          final cleanup = await _cleanOrphanedFiles();
          pendingRemoved += cleanup.pendingRemoved;
          orphanBackupsHandled += cleanup.backupsHandled;
          orphanFilesRemoved += cleanup.orphanFilesRemoved;
          failures += cleanup.failures;
        } on Object {
          // Cache recovery is best-effort and cannot block the primary reader.
          failures++;
        }
      }

      final report = CacheRecoveryReport(
        operationsRecovered: recovered,
        pendingFilesRemoved: pendingRemoved,
        orphanBackupsHandled: orphanBackupsHandled,
        orphanFilesRemoved: orphanFilesRemoved,
        failures: failures,
      );
      _lastRecoveryReport = report;
      return report;
    });
  }

  Future<bool> _recoverJournal(CacheOperationJournal journal) async {
    final payload = journal.payload;
    if (payload == null) return false;

    if (journal.operation == 'write') {
      final targetPath = _managedPayloadPath(payload['targetPath']);
      final temporaryPath = _managedPayloadPath(payload['temporaryPath']);
      final rawBackups = payload['backups'];
      if (targetPath == null || temporaryPath == null || rawBackups is! Map) return false;
      if (!await _isManagedPath(targetPath) || !await _isManagedPath(temporaryPath)) return false;

      final backups = <String, String>{};
      for (final item in rawBackups.entries) {
        final original = _managedPayloadPath(item.key);
        final backup = _managedPayloadPath(item.value);
        if (original == null || backup == null) return false;
        if (!await _isManagedPath(original) || !await _isManagedPath(backup)) return false;
        backups[original] = backup;
      }

      final temporary = File(temporaryPath);
      if (await temporary.exists()) await temporary.delete();

      // If the target had no prior file, it is a new uncommitted cache object.
      if (!backups.containsKey(targetPath)) {
        final target = File(targetPath);
        if (await target.exists()) await target.delete();
      }

      for (final backup in backups.entries.toList().reversed) {
        final original = File(backup.key);
        final staged = File(backup.value);
        if (await staged.exists()) {
          if (await original.exists()) await original.delete();
          await original.parent.create(recursive: true);
          await staged.rename(original.path);
        } else if (!await original.exists()) {
          // Both copies missing is not a safe rollback; retain the journal.
          return false;
        }
      }
      return true;
    }

    if (journal.operation == 'remove') {
      final originalPath = _managedPayloadPath(payload['originalPath']);
      final backupPath = _managedPayloadPath(payload['backupPath']);
      if (originalPath == null || backupPath == null) return false;
      if (!await _isManagedPath(originalPath) || !await _isManagedPath(backupPath)) return false;
      final original = File(originalPath);
      final backup = File(backupPath);
      final currentEntry = await database.findCacheEntry(journal.key);

      if (currentEntry == null) {
        // Metadata no longer refers to this key, so removal has effectively
        // committed. The remaining backup is disposable.
        if (await backup.exists()) await backup.delete();
        return true;
      }

      if (await backup.exists()) {
        if (await original.exists()) await original.delete();
        await original.parent.create(recursive: true);
        await backup.rename(original.path);
      } else if (!await original.exists()) {
        // No bytes survive. Clear the disposable cache index row and journal
        // in one transaction rather than leave a broken cache hit behind.
        await database.confirmCacheEviction([journal.key], journalId: journal.id);
      }
      return true;
    }

    return false;
  }

  String? _managedPayloadPath(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final normalized = path.normalize(path.absolute(value));
    // A journal is persisted data, not trusted filesystem instructions.
    // Never allow a corrupt row to direct recovery outside the cache root.
    final root = path.normalize(path.absolute(_rootDirectory.path));
    if (!path.isWithin(root, normalized)) return null;
    return normalized;
  }

  Future<_CleanupResult> _cleanOrphanedFiles() async {
    var pendingRemoved = 0;
    var backupsHandled = 0;
    var orphanFilesRemoved = 0;
    var failures = 0;
    final entities = <String>[];
    try {
      await for (final entity in _rootDirectory.list(recursive: true, followLinks: false)) {
        final type = await FileSystemEntity.type(entity.path, followLinks: false);
        if (type == FileSystemEntityType.file && await _isManagedPath(entity.path)) {
          entities.add(path.normalize(path.absolute(entity.path)));
        }
      }
    } on Object {
      return const _CleanupResult(failures: 1);
    }
    entities.sort();

    // Pending files were never installed as committed cache targets.
    for (final filePath in entities.where((p) => p.contains('.pending-'))) {
      try {
        await File(filePath).delete();
        pendingRemoved++;
      } on Object {
        failures++;
      }
    }

    // Handle old pre-journal backups and leftovers after a committed metadata
    // transaction. Refuse to follow symlinks or touch paths outside this root.
    final cacheEntries = await database.loadCacheEntries();
    final entriesByPath = <String, CacheEntryFile>{
      for (final entry in cacheEntries)
        path.normalize(path.absolute(entry.filePath)): entry,
    };
    final backupFiles = entities.where((p) => p.contains('.rollback-') || p.contains('.remove-')).toList();
    for (final backupPath in backupFiles) {
      final markerIndex = <int>[
        backupPath.lastIndexOf('.rollback-'),
        backupPath.lastIndexOf('.remove-'),
      ].where((index) => index >= 0).fold<int>(-1, (best, value) => value > best ? value : best);
      if (markerIndex < 0) continue;
      final originalPath = backupPath.substring(0, markerIndex);
      final backup = File(backupPath);
      final original = File(originalPath);
      try {
        if (!await _isManagedPath(originalPath)) {
          failures++;
          continue;
        }
        final reference = entriesByPath[originalPath];
        if (reference != null && !await original.exists()) {
          await original.parent.create(recursive: true);
          await backup.rename(original.path);
          backupsHandled++;
          continue;
        }
        if (reference != null && await original.exists()) {
          final originalLength = await original.length();
          final backupLength = await backup.length();
          if (originalLength != reference.entry.bytes && backupLength == reference.entry.bytes) {
            await original.delete();
            await backup.rename(original.path);
            backupsHandled++;
          } else if (originalLength == reference.entry.bytes) {
            await backup.delete();
            backupsHandled++;
          }
          // If neither copy matches durable metadata, preserve both for safety.
          continue;
        }
        // No cache metadata points at the original path (usually an evicted
        // entry after a committed write), so the old bytes are disposable.
        await backup.delete();
        backupsHandled++;
      } on Object {
        failures++;
      }
    }

    // Only delete unindexed .bin cache targets. Unknown files are left alone.
    final freshEntries = await database.loadCacheEntries();
    final referencedPaths = freshEntries
        .map((entry) => path.normalize(path.absolute(entry.filePath)))
        .toSet();
    for (final filePath in entities.where((p) => p.endsWith('.bin'))) {
      try {
        if (referencedPaths.contains(filePath) || !await File(filePath).exists()) continue;
        await File(filePath).delete();
        orphanFilesRemoved++;
      } on Object {
        failures++;
      }
    }

    return _CleanupResult(
      pendingRemoved: pendingRemoved,
      backupsHandled: backupsHandled,
      orphanFilesRemoved: orphanFilesRemoved,
      failures: failures,
    );
  }

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
      if (!await _isManagedPath(filePath)) {
        throw StateError('Refusing to evict a cache path outside the managed cache directory.');
      }
    }

    final nonce = DateTime.now().microsecondsSinceEpoch;
    final temporary = File(target.path + '.pending-' + nonce.toString());
    final backupPaths = <String, String>{};
    for (final originalPath in pathsToStage) {
      if (await File(originalPath).exists()) {
        backupPaths[originalPath] = originalPath + '.rollback-' + nonce.toString();
      }
    }
    if (await target.exists() && !backupPaths.containsKey(target.path)) {
      backupPaths[target.path] = target.path + '.rollback-' + nonce.toString();
    }

    final journalId = 'write-' + nonce.toString();
    // This durable journal is committed before any existing bytes are moved.
    // commitCacheWrite removes it in the same SQLite transaction as metadata.
    await database.beginCacheOperationJournal(
      id: journalId,
      operation: 'write',
      key: key,
      payload: <String, Object?>{
        'targetPath': target.path,
        'temporaryPath': temporary.path,
        'backups': backupPaths,
      },
    );

    final stagedBackups = <String, String>{};
    var targetInstalled = false;
    var metadataCommitted = false;
    try {
      await temporary.writeAsBytes(bytes, flush: true);

      for (final originalPath in pathsToStage) {
        final backupPath = backupPaths[originalPath];
        if (backupPath == null) continue;
        final original = File(originalPath);
        if (!await original.exists()) {
          throw StateError('A cache file changed while its write was being staged.');
        }
        await original.rename(backupPath);
        stagedBackups[originalPath] = backupPath;
      }

      // If an existing file at the final target was not one of the planned
      // evictions, stage it too before the rename can overwrite its contents.
      if (await target.exists() && !stagedBackups.containsKey(target.path)) {
        final backupPath = backupPaths[target.path];
        if (backupPath == null) {
          throw StateError('A cache target appeared while its write was being staged.');
        }
        await target.rename(backupPath);
        stagedBackups[target.path] = backupPath;
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
      await database.commitCacheWrite(
        entry,
        evictedKeys: evictedKeys,
        journalId: journalId,
      );
      metadataCommitted = true;

      // Once SQLite has committed, leftover backups are disposable cache files.
      for (final backupPath in backupPaths.values) {
        try {
          final backup = File(backupPath);
          if (await backup.exists()) await backup.delete();
        } on Object {
          // Startup recovery cleans disposable leftovers after committed writes.
        }
      }
      return entry;
    } catch (_) {
      if (metadataCommitted) rethrow;
      var rollbackComplete = true;
      if (targetInstalled && await target.exists()) {
        try {
          await target.delete();
        } on Object {
          rollbackComplete = false;
        }
      }
      for (final backup in stagedBackups.entries.toList().reversed) {
        try {
          final backupFile = File(backup.value);
          if (await backupFile.exists()) {
            final original = File(backup.key);
            await original.parent.create(recursive: true);
            if (await original.exists()) await original.delete();
            await backupFile.rename(original.path);
          }
        } on Object {
          rollbackComplete = false;
        }
      }
      for (final originalPath in backupPaths.keys) {
        if (!stagedBackups.containsKey(originalPath) && !await File(originalPath).exists()) {
          rollbackComplete = false;
        }
      }
      try {
        if (await temporary.exists()) await temporary.delete();
      } on Object {
        rollbackComplete = false;
      }
      if (rollbackComplete) {
        try {
          await database.removeCacheOperationJournal(journalId);
        } on Object {
          // A leftover journal is safe: recovery is idempotent after rollback.
        }
      }
      rethrow;
    }
  }

  /// Removes a cache file and its index record as one recoverable operation.
  Future<void> remove(String key) {
    if (_disposed) throw StateError('Cache storage service is disposed.');
    return _enqueue(() async {
      final entry = await database.findCacheEntry(key);
      if (entry == null) return;
      if (!await _isManagedPath(entry.filePath)) {
        throw StateError('Refusing to remove a cache path outside the managed cache directory.');
      }
      final original = File(entry.filePath);
      final nonce = DateTime.now().microsecondsSinceEpoch;
      final backup = File(entry.filePath + '.remove-' + nonce.toString());
      final journalId = 'remove-' + nonce.toString();
      await database.beginCacheOperationJournal(
        id: journalId,
        operation: 'remove',
        key: key,
        payload: <String, Object?>{
          'originalPath': original.path,
          'backupPath': backup.path,
        },
      );
      var staged = false;
      var metadataRemoved = false;
      try {
        if (await original.exists()) {
          await original.rename(backup.path);
          staged = true;
        }
        await database.confirmCacheEviction([key], journalId: journalId);
        metadataRemoved = true;
        if (staged && await backup.exists()) {
          try {
            await backup.delete();
          } on Object {
            // Metadata is committed; startup cleanup removes this backup.
          }
        }
      } catch (_) {
        if (metadataRemoved) rethrow;
        var rollbackComplete = true;
        if (staged && await backup.exists()) {
          try {
            if (await original.exists()) await original.delete();
            await original.parent.create(recursive: true);
            await backup.rename(original.path);
          } on Object {
            rollbackComplete = false;
          }
        } else if (staged && !await original.exists()) {
          rollbackComplete = false;
        }
        if (rollbackComplete) {
          try {
            await database.removeCacheOperationJournal(journalId);
          } on Object {
            // Preserve the journal if cleanup fails; recovery is idempotent.
          }
        }
        rethrow;
      }
    });
  }

  Future<bool> _isManagedPath(String candidate) async {
    final root = path.normalize(path.absolute(_rootDirectory.path));
    final file = path.normalize(path.absolute(candidate));
    if (!path.isWithin(root, file)) return false;

    // A path can be lexically inside the cache while a symlink redirects it
    // outside. Refuse any symlink along the managed path before rename/delete.
    var current = root;
    final relative = path.relative(file, from: root);
    for (final segment in path.split(relative)) {
      current = path.join(current, segment);
      if (await FileSystemEntity.type(current, followLinks: false) == FileSystemEntityType.link) {
        return false;
      }
    }
    return true;
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

class _CleanupResult {
  const _CleanupResult({
    this.pendingRemoved = 0,
    this.backupsHandled = 0,
    this.orphanFilesRemoved = 0,
    this.failures = 0,
  });

  final int pendingRemoved;
  final int backupsHandled;
  final int orphanFilesRemoved;
  final int failures;
}
