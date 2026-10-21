import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:kurotoon_flutter/storage/cache_storage_service.dart';
import 'package:kurotoon_flutter/storage/kurotoon_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory temp;
  late KurotoonDatabase database;
  late CacheStorageService cache;
  const budget = StorageBudget(maxBytes: 100);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kurotoon-cache-recovery-test-');
    database = await KurotoonDatabase.open(
      databasePath: p.join(temp.path, 'test.db'),
      factory: databaseFactoryFfi,
    );
    cache = await CacheStorageService.create(
      database: database,
      budget: budget,
      rootDirectory: Directory(p.join(temp.path, 'cache')),
    );
  });

  tearDown(() async {
    await cache.dispose();
    await database.close();
    await temp.delete(recursive: true);
  });

  test('startup recovery rolls back a write interrupted after staging', () async {
    final original = await cache.writeBytes(
      key: 'cover:original',
      bucket: CacheBucket.cover,
      bytes: [1, 2, 3, 4],
    );
    final originalBytes = await File(original.filePath).readAsBytes();
    final root = cache.rootDirectory;
    await cache.dispose();

    const nonce = 'crash-101';
    final backupPath = original.filePath + '.rollback-' + nonce;
    final target = File(p.join(root.path, 'cover', 'interrupted-target.bin'));
    final temporary = File(target.path + '.pending-' + nonce);
    await File(original.filePath).rename(backupPath);
    await target.parent.create(recursive: true);
    await target.writeAsBytes([9, 9, 9]);
    await temporary.writeAsBytes([8, 8]);

    await database.beginCacheOperationJournal(
      id: 'write-' + nonce,
      operation: 'write',
      key: 'cover:incoming',
      payload: {
        'targetPath': target.path,
        'temporaryPath': temporary.path,
        'backups': {original.filePath: backupPath},
      },
    );

    cache = await CacheStorageService.create(
      database: database,
      budget: budget,
      rootDirectory: root,
    );

    expect(await File(original.filePath).readAsBytes(), originalBytes);
    expect(await target.exists(), isFalse);
    expect(await temporary.exists(), isFalse);
    expect(await File(backupPath).exists(), isFalse);
    expect(await database.findCacheEntry('cover:original'), isNotNull);
    expect(await database.findCacheEntry('cover:incoming'), isNull);
    expect(await database.loadCacheOperationJournals(), isEmpty);
    expect(cache.lastRecoveryReport.operationsRecovered, 1);
    expect(cache.lastRecoveryReport.complete, isTrue);
  });

  test('startup recovery restores a removal interrupted before metadata commit', () async {
    final original = await cache.writeBytes(
      key: 'page:must-survive',
      bucket: CacheBucket.page,
      bytes: [4, 5, 6, 7],
      pinned: true,
    );
    final originalBytes = await File(original.filePath).readAsBytes();
    final root = cache.rootDirectory;
    await cache.dispose();

    const nonce = 'crash-202';
    final backupPath = original.filePath + '.remove-' + nonce;
    await File(original.filePath).rename(backupPath);
    await database.beginCacheOperationJournal(
      id: 'remove-' + nonce,
      operation: 'remove',
      key: 'page:must-survive',
      payload: {
        'originalPath': original.filePath,
        'backupPath': backupPath,
      },
    );

    cache = await CacheStorageService.create(
      database: database,
      budget: budget,
      rootDirectory: root,
    );

    expect(await File(original.filePath).readAsBytes(), originalBytes);
    expect(await File(backupPath).exists(), isFalse);
    expect((await database.findCacheEntry('page:must-survive'))?.entry.pinned, isTrue);
    expect(await database.loadCacheOperationJournals(), isEmpty);
    expect(cache.lastRecoveryReport.operationsRecovered, 1);
    expect(cache.lastRecoveryReport.complete, isTrue);
  });

  test('cleans unindexed pending files, committed backup orphans and unreferenced cache files', () async {
    final original = await cache.writeBytes(
      key: 'cover:kept',
      bucket: CacheBucket.cover,
      bytes: [1, 3, 5, 7],
    );
    final root = cache.rootDirectory;
    final backup = File(original.filePath + '.rollback-old');
    await File(original.filePath).copy(backup.path);
    final pending = File(original.filePath + '.pending-old');
    await pending.writeAsBytes([0, 0]);
    final orphan = File(p.join(root.path, 'cover', 'not-indexed.bin'));
    await orphan.writeAsBytes([2, 2, 2]);

    final report = await cache.recoverInterruptedOperations();

    expect(await File(original.filePath).readAsBytes(), [1, 3, 5, 7]);
    expect(await backup.exists(), isFalse);
    expect(await pending.exists(), isFalse);
    expect(await orphan.exists(), isFalse);
    expect(report.pendingFilesRemoved, 1);
    expect(report.orphanBackupsHandled, 1);
    expect(report.orphanFilesRemoved, 1);
    expect(report.complete, isTrue);
  });

  test('schema version 7 upgrades to the operation journal without losing cache rows', () async {
    final oldPath = p.join(temp.path, 'schema-v7.db');
    final old = await databaseFactoryFfi.openDatabase(
      oldPath,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE cache_entries (
              cache_key TEXT PRIMARY KEY NOT NULL,
              bucket TEXT NOT NULL,
              bytes INTEGER NOT NULL,
              file_path TEXT NOT NULL,
              last_accessed_at INTEGER NOT NULL,
              pinned INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.insert('cache_entries', {
            'cache_key': 'existing-cache-row',
            'bucket': CacheBucket.cover.name,
            'bytes': 3,
            'file_path': p.join(temp.path, 'old-cache.bin'),
            'last_accessed_at': 1,
            'pinned': 0,
          });
        },
      ),
    );
    await old.close();

    final upgraded = await KurotoonDatabase.open(
      databasePath: oldPath,
      factory: databaseFactoryFfi,
    );
    final rows = await upgraded.rawDatabase.query('cache_entries');
    final journalTable = await upgraded.rawDatabase.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'cache_operation_journal'",
    );
    expect(rows, hasLength(1));
    expect(rows.single['cache_key'], 'existing-cache-row');
    expect(journalTable, hasLength(1));
    await upgraded.close();
  });
}
