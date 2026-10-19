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
  final budget = StorageBudget(maxBytes: 100);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kurotoon-cache-service-test-');
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

  test('enforces budget and evicts unpinned cache before committing new bytes', () async {
    final response = await cache.writeBytes(
      key: 'search:blue-star',
      bucket: CacheBucket.providerResponse,
      bytes: List<int>.filled(60, 1),
    );
    final pinned = await cache.writeBytes(
      key: 'offline:chapter-1',
      bucket: CacheBucket.page,
      bytes: List<int>.filled(20, 2),
      pinned: true,
    );
    expect(await File(response.filePath).exists(), isTrue);
    expect(await File(pinned.filePath).exists(), isTrue);

    final incoming = await cache.writeBytes(
      key: 'cover:blue-star',
      bucket: CacheBucket.cover,
      bytes: List<int>.filled(30, 3),
    );

    expect(await File(response.filePath).exists(), isFalse);
    expect(await File(pinned.filePath).exists(), isTrue);
    expect(await File(incoming.filePath).readAsBytes(), List<int>.filled(30, 3));
    final rows = await database.loadCacheEntries();
    expect(rows.map((row) => row.entry.key).toSet(), {'offline:chapter-1', 'cover:blue-star'});
    expect(rows.fold<int>(0, (sum, row) => sum + row.entry.bytes), 50);
  });

  test('rejects writes when pinned content prevents a safe eviction', () async {
    final pinned = await cache.writeBytes(
      key: 'offline:must-survive',
      bucket: CacheBucket.page,
      bytes: List<int>.filled(80, 7),
      pinned: true,
    );

    await expectLater(
      cache.writeBytes(
        key: 'too-large-for-remaining-budget',
        bucket: CacheBucket.audio,
        bytes: List<int>.filled(30, 8),
      ),
      throwsA(isA<CacheWriteRejected>()),
    );

    expect(await File(pinned.filePath).readAsBytes(), List<int>.filled(80, 7));
    expect((await database.loadCacheEntries()).map((row) => row.entry.key), ['offline:must-survive']);
  });

  test('replacing an entry does not double-count old bytes and preserves its pin', () async {
    final first = await cache.writeBytes(
      key: 'offline:chapter',
      bucket: CacheBucket.page,
      bytes: List<int>.filled(70, 1),
      pinned: true,
    );
    final replacement = await cache.writeBytes(
      key: 'offline:chapter',
      bucket: CacheBucket.page,
      bytes: List<int>.filled(90, 2),
    );

    expect(first.filePath, replacement.filePath);
    expect(await File(replacement.filePath).readAsBytes(), List<int>.filled(90, 2));
    final entries = await database.loadCacheEntries();
    expect(entries, hasLength(1));
    expect(entries.single.entry.bytes, 90);
    expect(entries.single.entry.pinned, isTrue);
  });

  test('restores staged files when SQLite rejects the cache metadata commit', () async {
    final existing = await cache.writeBytes(
      key: 'existing-response',
      bucket: CacheBucket.providerResponse,
      bytes: List<int>.filled(70, 4),
    );
    await database.rawDatabase.execute('''
      CREATE TRIGGER reject_incoming_cache
      BEFORE INSERT ON cache_entries
      WHEN NEW.cache_key = 'incoming'
      BEGIN
        SELECT RAISE(ABORT, 'simulated metadata failure');
      END;
    ''');

    await expectLater(
      cache.writeBytes(
        key: 'incoming',
        bucket: CacheBucket.cover,
        bytes: List<int>.filled(60, 5),
      ),
      throwsA(anything),
    );

    expect(await File(existing.filePath).readAsBytes(), List<int>.filled(70, 4));
    final entries = await database.loadCacheEntries();
    expect(entries, hasLength(1));
    expect(entries.single.entry.key, 'existing-response');
  });

  test('serializes concurrent writes so the budget cannot be oversubscribed', () async {
    final results = await Future.wait([
      cache.writeBytes(
        key: 'cover:a',
        bucket: CacheBucket.cover,
        bytes: List<int>.filled(60, 1),
      ),
      cache.writeBytes(
        key: 'cover:b',
        bucket: CacheBucket.cover,
        bytes: List<int>.filled(60, 2),
      ),
    ]);

    expect(results, hasLength(2));
    final entries = await database.loadCacheEntries();
    expect(entries.fold<int>(0, (sum, row) => sum + row.entry.bytes), lessThanOrEqualTo(100));
    expect(entries, hasLength(1));
    expect(await File(entries.single.filePath).exists(), isTrue);
  });

  test('refuses to remove a cache record whose path escapes the managed directory', () async {
    await database.saveCacheEntry(CacheEntryFile(
      entry: CacheEntry(
        key: 'foreign-path',
        bucket: CacheBucket.other,
        bytes: 3,
        lastAccessedAt: DateTime.now(),
      ),
      filePath: p.join(temp.path, 'outside.bin'),
    ));

    await expectLater(cache.remove('foreign-path'), throwsStateError);
    expect((await database.loadCacheEntries()).single.entry.key, 'foreign-path');
  });
}
