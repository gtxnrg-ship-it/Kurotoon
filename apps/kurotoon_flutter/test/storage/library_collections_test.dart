import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_flutter/storage/kurotoon_database.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('collections are durable, idempotent, and independent of saved stories', () async {
    final directory = await Directory.systemTemp.createTemp('kurotoon-collections-');
    final database = await KurotoonDatabase.open(
      databasePath: path.join(directory.path, 'kurotoon.db'),
      factory: databaseFactoryFfi,
    );
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    await _seedSavedStory(database);
    await database.createLibraryCollection(id: 'collection-favorites', name: '  Favorite   stories  ');

    final created = await database.loadLibraryCollections();
    expect(created, hasLength(1));
    expect(created.single.name, 'Favorite stories');
    expect(created.single.itemCount, 0);

    expect(
      await database.addLibraryEntryToCollection(
        collectionId: 'collection-favorites',
        workId: 'work-1',
        editionId: 'edition-1',
      ),
      isTrue,
    );
    expect(
      await database.addLibraryEntryToCollection(
        collectionId: 'collection-favorites',
        workId: 'work-1',
        editionId: 'edition-1',
      ),
      isFalse,
      reason: 'Repeated taps must not create duplicate memberships.',
    );

    final collection = (await database.loadLibraryCollections()).single;
    expect(collection.itemCount, 1);
    expect(await database.loadLibraryCollectionEditionIds(collection.id), {'edition-1'});
    await expectLater(
      database.createLibraryCollection(id: 'collection-duplicate', name: 'favorite stories'),
      throwsA(isA<Exception>()),
      reason: 'Collection names should be unique without case sensitivity.',
    );

    // Removing organization must never remove the durable library row.
    await database.removeLibraryCollection(collection.id);
    expect(await database.loadLibraryCollections(), isEmpty);
    expect(await database.loadLibraryRecord('work-1', 'edition-1'), isNotNull);
  });

  test('removing a saved story also removes its collection memberships', () async {
    final directory = await Directory.systemTemp.createTemp('kurotoon-collection-removal-');
    final database = await KurotoonDatabase.open(
      databasePath: path.join(directory.path, 'kurotoon.db'),
      factory: databaseFactoryFfi,
    );
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    await _seedSavedStory(database);
    await database.createLibraryCollection(id: 'collection-later', name: 'Read later');
    await database.addLibraryEntryToCollection(
      collectionId: 'collection-later',
      workId: 'work-1',
      editionId: 'edition-1',
    );

    expect(
      await database.removeLibraryEntryFromCollection(
        collectionId: 'collection-later',
        workId: 'work-1',
        editionId: 'edition-1',
      ),
      isTrue,
    );
    expect(await database.loadLibraryCollectionEditionIds('collection-later'), isEmpty);

    await database.addLibraryEntryToCollection(
      collectionId: 'collection-later',
      workId: 'work-1',
      editionId: 'edition-1',
    );
    await database.removeLibraryRecord('work-1', 'edition-1');
    expect(await database.loadLibraryCollectionEditionIds('collection-later'), isEmpty);
    expect((await database.loadLibraryCollections()).single.itemCount, 0);
  });

  test('schema version 6 upgrades to collections without deleting saved membership', () async {
    final directory = await Directory.systemTemp.createTemp('kurotoon-collection-migration-');
    final databasePath = path.join(directory.path, 'kurotoon-v6.db');
    final oldDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          // Minimal v6 parent table: the upgrade should only add collection tables.
          await db.execute('''
            CREATE TABLE library_entries (
              work_id TEXT NOT NULL,
              edition_id TEXT NOT NULL,
              PRIMARY KEY(work_id, edition_id)
            )
          ''');
          await db.insert('library_entries', {
            'work_id': 'legacy-work',
            'edition_id': 'legacy-edition',
          });
        },
      ),
    );
    await oldDatabase.close();

    final database = await KurotoonDatabase.open(
      databasePath: databasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    expect((await database.rawDatabase.query('library_entries')), hasLength(1));
    expect(await database.loadLibraryCollections(), isEmpty);
    await database.createLibraryCollection(id: 'migrated-collection', name: 'After update');
    expect((await database.loadLibraryCollections()).single.name, 'After update');
  });
}

Future<void> _seedSavedStory(KurotoonDatabase database) async {
  await database.rawDatabase.insert('works', {
    'id': 'work-1',
    'canonical_title': 'Saved Story',
    'format': 'manga',
    'updated_at': 1,
  });
  await database.rawDatabase.insert('editions', {
    'id': 'edition-1',
    'work_id': 'work-1',
    'format': 'manga',
  });
  await database.putLibraryRecord(LibraryRecord(
    workId: 'work-1',
    editionId: 'edition-1',
    status: LibraryStatus.reading,
    addedAt: DateTime.utc(2026, 1, 1),
    sortOrder: 0,
  ));
}
