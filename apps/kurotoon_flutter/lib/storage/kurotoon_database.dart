import 'dart:convert';
import 'dart:io';

import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

enum LibraryStatus { reading, completed, planned, paused, dropped, rereading }

class LibraryRecord {
  const LibraryRecord({
    required this.workId,
    required this.editionId,
    required this.status,
    required this.addedAt,
    required this.sortOrder,
    this.lastOpenedAt,
  });

  final String workId;
  final String editionId;
  final LibraryStatus status;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;
  final int sortOrder;
}

class CacheEntryFile {
  const CacheEntryFile({required this.entry, required this.filePath});

  final CacheEntry entry;
  final String filePath;
}

class CacheWritePlan {
  const CacheWritePlan({
    required this.storagePlan,
    required this.filesToEvict,
  });

  final StoragePlan storagePlan;
  final List<String> filesToEvict;
}

/// SQLite persistence for user-owned state and normalized catalog metadata.
/// Image/page/audio bytes live in bounded files, not database blobs.
class KurotoonDatabase {
  KurotoonDatabase._(this._database);

  final Database _database;
  bool _closed = false;

  Database get rawDatabase {
    _ensureOpen();
    return _database;
  }

  static const int schemaVersion = 2;

  static Future<KurotoonDatabase> open({
    String? databasePath,
    DatabaseFactory? factory,
  }) async {
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (factory == null && isDesktop) sqfliteFfiInit();
    final DatabaseFactory selectedFactory =
        factory ?? (isDesktop ? databaseFactoryFfi : databaseFactory);
    final String resolvedPath;
    if (databasePath != null) {
      resolvedPath = databasePath;
    } else {
      resolvedPath = path.join((await getApplicationSupportDirectory()).path, 'kurotoon.db');
    }
    final database = await selectedFactory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    return KurotoonDatabase._(database);
  }

  static Future<void> _createSchema(DatabaseExecutor db, int version) async {
    const statements = <String>[
      '''CREATE TABLE works (
        id TEXT PRIMARY KEY NOT NULL,
        canonical_title TEXT NOT NULL,
        alternate_titles_json TEXT NOT NULL DEFAULT '[]',
        creator_names_json TEXT NOT NULL DEFAULT '[]',
        year INTEGER,
        format TEXT NOT NULL,
        locked_distinct_identity INTEGER NOT NULL DEFAULT 0,
        verified INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )''',
      '''CREATE TABLE provider_listings (
        provider_id TEXT NOT NULL,
        external_id TEXT NOT NULL,
        work_id TEXT NOT NULL,
        title TEXT NOT NULL,
        alternate_titles_json TEXT NOT NULL DEFAULT '[]',
        creator_names_json TEXT NOT NULL DEFAULT '[]',
        year INTEGER,
        format TEXT NOT NULL,
        language TEXT,
        description TEXT,
        cover_url TEXT,
        provider_url TEXT NOT NULL,
        tags_json TEXT NOT NULL DEFAULT '[]',
        PRIMARY KEY(provider_id, external_id),
        FOREIGN KEY(work_id) REFERENCES works(id) ON UPDATE CASCADE ON DELETE RESTRICT
      )''',
      'CREATE INDEX provider_listings_work_idx ON provider_listings(work_id)',
      '''CREATE TABLE editions (
        id TEXT PRIMARY KEY NOT NULL,
        work_id TEXT NOT NULL,
        title TEXT,
        language_code TEXT,
        release_year INTEGER,
        format TEXT NOT NULL,
        is_official INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(work_id) REFERENCES works(id) ON UPDATE CASCADE ON DELETE RESTRICT
      )''',
      '''CREATE TABLE chapters (
        id TEXT PRIMARY KEY NOT NULL,
        edition_id TEXT NOT NULL,
        title TEXT,
        chapter_number REAL,
        volume_number INTEGER,
        kind TEXT NOT NULL,
        mini_group_id TEXT,
        mini_index INTEGER,
        mini_count INTEGER,
        FOREIGN KEY(edition_id) REFERENCES editions(id) ON UPDATE CASCADE ON DELETE RESTRICT
      )''',
      '''CREATE TABLE chapter_listings (
        provider_id TEXT NOT NULL,
        external_id TEXT NOT NULL,
        chapter_id TEXT NOT NULL,
        url TEXT NOT NULL,
        language_code TEXT,
        release_group TEXT,
        published_at INTEGER,
        is_official_translation INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(provider_id, external_id),
        FOREIGN KEY(chapter_id) REFERENCES chapters(id) ON UPDATE CASCADE ON DELETE CASCADE
      )''',
      '''CREATE TABLE library_entries (
        work_id TEXT NOT NULL,
        edition_id TEXT NOT NULL,
        status TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        last_opened_at INTEGER,
        sort_order INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(work_id, edition_id),
        FOREIGN KEY(work_id) REFERENCES works(id) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(edition_id) REFERENCES editions(id) ON UPDATE CASCADE ON DELETE RESTRICT
      )''',
      '''CREATE TABLE reading_progress (
        work_id TEXT NOT NULL,
        edition_id TEXT NOT NULL,
        chapter_id TEXT NOT NULL,
        anchor TEXT,
        fraction REAL NOT NULL,
        updated_at INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(work_id, edition_id)
      )''',
      '''CREATE TABLE app_settings (
        key TEXT PRIMARY KEY NOT NULL,
        value_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )''',
      '''CREATE TABLE provider_settings (
        provider_id TEXT PRIMARY KEY NOT NULL,
        enabled INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''',
      '''CREATE TABLE creator_profiles (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        aliases_json TEXT NOT NULL DEFAULT '[]'
      )''',
      '''CREATE TABLE creator_credits (
        creator_id TEXT NOT NULL,
        work_id TEXT NOT NULL,
        edition_id TEXT,
        provider_id TEXT,
        role TEXT NOT NULL,
        PRIMARY KEY(creator_id, work_id, role, edition_id, provider_id),
        FOREIGN KEY(creator_id) REFERENCES creator_profiles(id) ON UPDATE CASCADE ON DELETE CASCADE,
        FOREIGN KEY(work_id) REFERENCES works(id) ON UPDATE CASCADE ON DELETE RESTRICT
      )''',
      '''CREATE TABLE identity_review_queue (
        listing_key TEXT PRIMARY KEY NOT NULL,
        candidate_json TEXT NOT NULL,
        reason_json TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''',
      '''CREATE TABLE cache_entries (
        cache_key TEXT PRIMARY KEY NOT NULL,
        bucket TEXT NOT NULL,
        bytes INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        last_accessed_at INTEGER NOT NULL,
        pinned INTEGER NOT NULL DEFAULT 0
      )''',
      '''CREATE TABLE voice_pack_installs (
        pack_id TEXT PRIMARY KEY NOT NULL,
        version TEXT NOT NULL,
        locale TEXT NOT NULL,
        license_id TEXT NOT NULL,
        sha256 TEXT NOT NULL,
        install_path TEXT NOT NULL,
        installed_at INTEGER NOT NULL
      )''',
      '''CREATE TABLE extension_repositories (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        index_url TEXT NOT NULL UNIQUE,
        description TEXT,
        website_url TEXT,
        icon_url TEXT,
        trust TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        last_checked_at INTEGER,
        last_index_digest TEXT
      )''',
      '''CREATE TABLE installed_extensions (
        extension_id TEXT PRIMARY KEY NOT NULL,
        repository_id TEXT NOT NULL,
        name TEXT NOT NULL,
        version TEXT NOT NULL,
        manifest_url TEXT NOT NULL,
        sha256 TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 0,
        install_path TEXT,
        installed_at INTEGER NOT NULL,
        FOREIGN KEY(repository_id) REFERENCES extension_repositories(id)
          ON UPDATE CASCADE ON DELETE RESTRICT
      )''',
      'CREATE INDEX installed_extensions_repo_idx ON installed_extensions(repository_id)',
    ];
    for (final statement in statements) {
      await db.execute(statement);
    }
  }

  static Future<void> _upgradeSchema(DatabaseExecutor db, int oldVersion, int newVersion) async {
    if (oldVersion < 1 && newVersion >= 1) await _createSchema(db, newVersion);
    if (oldVersion < 2 && newVersion >= 2) await _createExtensionSchema(db);
  }

  static Future<void> _createExtensionSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS extension_repositories (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      index_url TEXT NOT NULL UNIQUE,
      description TEXT,
      website_url TEXT,
      icon_url TEXT,
      trust TEXT NOT NULL,
      added_at INTEGER NOT NULL,
      last_checked_at INTEGER,
      last_index_digest TEXT
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS installed_extensions (
      extension_id TEXT PRIMARY KEY NOT NULL,
      repository_id TEXT NOT NULL,
      name TEXT NOT NULL,
      version TEXT NOT NULL,
      manifest_url TEXT NOT NULL,
      sha256 TEXT NOT NULL,
      size_bytes INTEGER NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 0,
      install_path TEXT,
      installed_at INTEGER NOT NULL,
      FOREIGN KEY(repository_id) REFERENCES extension_repositories(id)
        ON UPDATE CASCADE ON DELETE RESTRICT
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS installed_extensions_repo_idx ON installed_extensions(repository_id)');
  }

  Future<void> upsertCatalogEntry(CatalogEntry entry) async {
    _ensureOpen();
    await _database.transaction((tx) async {
      final work = entry.work;
      final workRow = <String, Object?>{
        'id': work.id,
        'canonical_title': work.title,
        'alternate_titles_json': jsonEncode(work.alternateTitles),
        'creator_names_json': jsonEncode(work.creatorNames),
        'year': work.year,
        'format': work.format.name,
        'locked_distinct_identity': work.lockedDistinctIdentity ? 1 : 0,
        'verified': entry.verified ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
      final exists = await tx.query('works', columns: ['id'], where: 'id = ?', whereArgs: [work.id], limit: 1);
      if (exists.isEmpty) {
        await tx.insert('works', workRow);
      } else {
        await tx.update('works', workRow, where: 'id = ?', whereArgs: [work.id]);
      }

      for (final listing in entry.listings) {
        await tx.insert(
          'provider_listings',
          {
            'provider_id': listing.providerId,
            'external_id': listing.externalId,
            'work_id': work.id,
            'title': listing.title,
            'alternate_titles_json': jsonEncode(listing.alternateTitles),
            'creator_names_json': jsonEncode(listing.creatorNames),
            'year': listing.year,
            'format': listing.format.name,
            'language': listing.language,
            'description': listing.description,
            'cover_url': listing.coverUrl?.toString(),
            'provider_url': listing.providerUrl.toString(),
            'tags_json': jsonEncode(listing.tags),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<CatalogEntry>> loadCatalog() async {
    _ensureOpen();
    final workRows = await _database.query('works', orderBy: 'canonical_title COLLATE NOCASE');
    final listingRows = await _database.query('provider_listings');
    final listingsByWork = <String, List<WorkCandidate>>{};
    for (final row in listingRows) {
      final candidate = _candidateFromRow(row);
      final workId = row['work_id'] as String;
      if (candidate != null) (listingsByWork[workId] ??= []).add(candidate);
    }
    return List.unmodifiable(workRows.map((row) {
      final work = WorkRecord(
        id: row['id'] as String,
        title: row['canonical_title'] as String,
        alternateTitles: _stringList(row['alternate_titles_json']),
        creatorNames: _stringList(row['creator_names_json']),
        year: row['year'] as int?,
        format: _enumByName(WorkFormat.values, row['format'] as String, WorkFormat.unknown),
        lockedDistinctIdentity: (row['locked_distinct_identity'] as int? ?? 0) == 1,
      );
      return CatalogEntry(
        work: work,
        listings: listingsByWork[work.id] ?? const [],
        verified: (row['verified'] as int? ?? 0) == 1,
      );
    }));
  }

  Future<void> upsertEdition(EditionRecord edition) async {
    _ensureOpen();
    await _database.transaction((tx) async {
      final exists = await tx.query('works', columns: ['id'], where: 'id = ?', whereArgs: [edition.workId], limit: 1);
      if (exists.isEmpty) throw StateError('Cannot store an edition without its catalog work.');
      final row = {
        'id': edition.id,
        'work_id': edition.workId,
        'title': edition.title,
        'language_code': edition.languageCode,
        'release_year': edition.releaseYear,
        'format': edition.format.name,
        'is_official': edition.isOfficial ? 1 : 0,
      };
      final prior = await tx.query('editions', columns: ['id'], where: 'id = ?', whereArgs: [edition.id], limit: 1);
      if (prior.isEmpty) {
        await tx.insert('editions', row);
      } else {
        await tx.update('editions', row, where: 'id = ?', whereArgs: [edition.id]);
      }
    });
  }

  Future<void> upsertChapter(ChapterUnit chapter) async {
    _ensureOpen();
    await _database.transaction((tx) async {
      final edition = await tx.query('editions', columns: ['id'], where: 'id = ?', whereArgs: [chapter.editionId], limit: 1);
      if (edition.isEmpty) throw StateError('Store the chapter edition before storing its chapters.');
      final row = {
        'id': chapter.id,
        'edition_id': chapter.editionId,
        'title': chapter.title,
        'chapter_number': chapter.chapterNumber,
        'volume_number': chapter.volumeNumber,
        'kind': chapter.kind.name,
        'mini_group_id': chapter.miniGroupId,
        'mini_index': chapter.miniIndex,
        'mini_count': chapter.miniCount,
      };
      final prior = await tx.query('chapters', columns: ['id'], where: 'id = ?', whereArgs: [chapter.id], limit: 1);
      if (prior.isEmpty) {
        await tx.insert('chapters', row);
      } else {
        await tx.update('chapters', row, where: 'id = ?', whereArgs: [chapter.id]);
      }
      for (final listing in chapter.listings) {
        await tx.insert(
          'chapter_listings',
          {
            'provider_id': listing.providerId,
            'external_id': listing.externalId,
            'chapter_id': chapter.id,
            'url': listing.url.toString(),
            'language_code': listing.languageCode,
            'release_group': listing.releaseGroup,
            'published_at': listing.publishedAt?.millisecondsSinceEpoch,
            'is_official_translation': listing.isOfficialTranslation ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<ChapterUnit>> loadChapters(String editionId) async {
    _ensureOpen();
    final rows = await _database.query(
      'chapters',
      where: 'edition_id = ?',
      whereArgs: [editionId],
      orderBy: 'chapter_number ASC, id ASC',
    );
    final result = <ChapterUnit>[];
    for (final row in rows) {
      final listingRows = await _database.query(
        'chapter_listings',
        where: 'chapter_id = ?',
        whereArgs: [row['id']],
      );
      final listings = <ChapterListing>[];
      for (final listing in listingRows) {
        final uri = Uri.tryParse(listing['url'] as String? ?? '');
        if (uri == null || !uri.isAbsolute || uri.host.isEmpty) continue;
        listings.add(ChapterListing(
          providerId: listing['provider_id'] as String,
          externalId: listing['external_id'] as String,
          url: uri,
          languageCode: listing['language_code'] as String?,
          releaseGroup: listing['release_group'] as String?,
          publishedAt: _dateFromMillis(listing['published_at'] as int?),
          isOfficialTranslation: (listing['is_official_translation'] as int? ?? 0) == 1,
        ));
      }
      result.add(ChapterUnit(
        id: row['id'] as String,
        editionId: row['edition_id'] as String,
        title: row['title'] as String?,
        chapterNumber: (row['chapter_number'] as num?)?.toDouble(),
        volumeNumber: row['volume_number'] as int?,
        kind: _enumByName(ChapterKind.values, row['kind'] as String, ChapterKind.regular),
        miniGroupId: row['mini_group_id'] as String?,
        miniIndex: row['mini_index'] as int?,
        miniCount: row['mini_count'] as int?,
        listings: listings,
      ));
    }
    return List.unmodifiable(result);
  }

  Future<void> putLibraryRecord(LibraryRecord record) async {
    _ensureOpen();
    await _database.transaction((tx) async {
      final work = await tx.query('works', columns: ['id'], where: 'id = ?', whereArgs: [record.workId], limit: 1);
      final edition = await tx.query(
        'editions',
        columns: ['id'],
        where: 'id = ? AND work_id = ?',
        whereArgs: [record.editionId, record.workId],
        limit: 1,
      );
      if (work.isEmpty || edition.isEmpty) {
        throw StateError('Catalog work and a matching edition must exist before adding them to the library.');
      }
      await tx.insert(
        'library_entries',
        {
          'work_id': record.workId,
          'edition_id': record.editionId,
          'status': record.status.name,
          'added_at': record.addedAt.millisecondsSinceEpoch,
          'last_opened_at': record.lastOpenedAt?.millisecondsSinceEpoch,
          'sort_order': record.sortOrder,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<LibraryRecord>> loadLibrary({LibraryStatus? status}) async {
    _ensureOpen();
    final rows = await _database.query(
      'library_entries',
      where: status == null ? null : 'status = ?',
      whereArgs: status == null ? null : [status.name],
      orderBy: 'sort_order ASC, added_at DESC',
    );
    return List.unmodifiable(rows.map((row) => LibraryRecord(
      workId: row['work_id'] as String,
      editionId: row['edition_id'] as String,
      status: _enumByName(LibraryStatus.values, row['status'] as String, LibraryStatus.reading),
      addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int),
      lastOpenedAt: _dateFromMillis(row['last_opened_at'] as int?),
      sortOrder: row['sort_order'] as int,
    )));
  }

  Future<ReadingProgress> saveProgress(ReadingProgress incoming) async {
    _ensureOpen();
    return _database.transaction((tx) async {
      final rows = await tx.query(
        'reading_progress',
        where: 'work_id = ? AND edition_id = ?',
        whereArgs: [incoming.workId, incoming.editionId],
        limit: 1,
      );
      final current = rows.isEmpty ? null : _progressFromRow(rows.single);
      final resolved = mergeProgress(current, incoming);
      await tx.insert(
        'reading_progress',
        {
          'work_id': resolved.workId,
          'edition_id': resolved.editionId,
          'chapter_id': resolved.chapterId,
          'anchor': resolved.anchor,
          'fraction': resolved.fraction,
          'updated_at': resolved.updatedAt.millisecondsSinceEpoch,
          'device_id': resolved.deviceId,
          'revision': resolved.revision,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return resolved;
    });
  }

  Future<ReadingProgress?> loadProgress(String workId, String editionId) async {
    _ensureOpen();
    final rows = await _database.query(
      'reading_progress',
      where: 'work_id = ? AND edition_id = ?',
      whereArgs: [workId, editionId],
      limit: 1,
    );
    return rows.isEmpty ? null : _progressFromRow(rows.single);
  }

  Future<void> setSetting(String key, Object? value) async {
    _ensureOpen();
    if (key.trim().isEmpty) throw ArgumentError.value(key, 'key');
    await _database.insert(
      'app_settings',
      {
        'key': key,
        'value_json': jsonEncode(value),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<T?> getSetting<T>(String key) async {
    _ensureOpen();
    final rows = await _database.query('app_settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final value = jsonDecode(rows.single['value_json'] as String);
    return value is T ? value : null;
  }


  Future<void> saveExtensionRepository(ExtensionRepository repository, {String? indexDigest}) async {
    _ensureOpen();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database.transaction((tx) async {
      final sameUrl = await tx.query(
        'extension_repositories',
        columns: ['id'],
        where: 'index_url = ?',
        whereArgs: [repository.indexUri.toString()],
        limit: 1,
      );
      if (sameUrl.isNotEmpty && sameUrl.single['id'] != repository.id) {
        throw StateError('This repository URL is already registered under another identity.');
      }
      final existing = await tx.query(
        'extension_repositories',
        columns: ['id', 'added_at', 'index_url'],
        where: 'id = ?',
        whereArgs: [repository.id],
        limit: 1,
      );
      if (existing.isNotEmpty && existing.single['index_url'] != repository.indexUri.toString()) {
        throw StateError('Changing a repository URL requires removing and re-adding it explicitly.');
      }
      final values = <String, Object?>{
        'id': repository.id,
        'name': repository.name,
        'index_url': repository.indexUri.toString(),
        'description': repository.description,
        'website_url': repository.website?.toString(),
        'icon_url': repository.iconUri?.toString(),
        'trust': repository.trust.name,
        'added_at': existing.isEmpty ? now : existing.single['added_at'],
        'last_checked_at': now,
        'last_index_digest': indexDigest,
      };
      if (existing.isEmpty) {
        await tx.insert('extension_repositories', values);
      } else {
        await tx.update('extension_repositories', values, where: 'id = ?', whereArgs: [repository.id]);
      }
    });
  }

  Future<List<Map<String, Object?>>> loadExtensionRepositories() async {
    _ensureOpen();
    final rows = await _database.query('extension_repositories', orderBy: 'name COLLATE NOCASE ASC');
    return List.unmodifiable(rows.map((row) => Map<String, Object?>.unmodifiable(row)));
  }

  Future<void> markRepositoryChecked(String repositoryId, {String? indexDigest}) async {
    _ensureOpen();
    await _database.update(
      'extension_repositories',
      {
        'last_checked_at': DateTime.now().millisecondsSinceEpoch,
        if (indexDigest != null) 'last_index_digest': indexDigest,
      },
      where: 'id = ?',
      whereArgs: [repositoryId],
    );
  }

  Future<void> removeExtensionRepository(String repositoryId) async {
    _ensureOpen();
    final installed = await _database.query(
      'installed_extensions',
      columns: ['extension_id'],
      where: 'repository_id = ?',
      whereArgs: [repositoryId],
      limit: 1,
    );
    if (installed.isNotEmpty) {
      throw StateError('Uninstall or move this repository’s extensions before removing the repository.');
    }
    await _database.delete('extension_repositories', where: 'id = ?', whereArgs: [repositoryId]);
  }

  Future<void> recordInstalledExtension({
    required ExtensionPackageEntry entry,
    required String repositoryId,
    required String installPath,
    bool enabled = false,
  }) async {
    _ensureOpen();
    final repo = await _database.query(
      'extension_repositories',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [repositoryId],
      limit: 1,
    );
    if (repo.isEmpty) throw StateError('Cannot install from an unknown repository.');
    final repositoryRows = await _database.query(
      'extension_repositories',
      columns: ['index_url'],
      where: 'id = ?',
      whereArgs: [repositoryId],
      limit: 1,
    );
    final repositoryUri = Uri.tryParse(repositoryRows.single['index_url'] as String);
    if (repositoryUri == null || repositoryUri.host.toLowerCase() != entry.manifestUri.host.toLowerCase()) {
      throw StateError('Extension package origin does not match its repository.');
    }
    final existingInstall = await _database.query(
      'installed_extensions',
      columns: ['repository_id'],
      where: 'extension_id = ?',
      whereArgs: [entry.id],
      limit: 1,
    );
    if (existingInstall.isNotEmpty && existingInstall.single['repository_id'] != repositoryId) {
      throw StateError('An extension with this ID is already installed from another repository.');
    }
    await _database.insert(
      'installed_extensions',
      {
        'extension_id': entry.id,
        'repository_id': repositoryId,
        'name': entry.name,
        'version': entry.version,
        'manifest_url': entry.manifestUri.toString(),
        'sha256': entry.sha256,
        'size_bytes': entry.sizeBytes,
        'enabled': enabled ? 1 : 0,
        'install_path': installPath,
        'installed_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> loadInstalledExtensions() async {
    _ensureOpen();
    final rows = await _database.query('installed_extensions', orderBy: 'name COLLATE NOCASE ASC');
    return List.unmodifiable(rows.map((row) => Map<String, Object?>.unmodifiable(row)));
  }

  Future<void> setExtensionEnabled(String extensionId, bool enabled) async {
    _ensureOpen();
    final changed = await _database.update(
      'installed_extensions',
      {'enabled': enabled ? 1 : 0},
      where: 'extension_id = ?',
      whereArgs: [extensionId],
    );
    if (changed == 0) throw ArgumentError.value(extensionId, 'extensionId', 'Extension is not installed.');
  }

  Future<void> removeInstalledExtension(String extensionId) async {
    _ensureOpen();
    await _database.delete('installed_extensions', where: 'extension_id = ?', whereArgs: [extensionId]);
  }

  Future<void> setProviderEnabled(String providerId, bool enabled) async {
    _ensureOpen();
    if (providerId.trim().isEmpty) throw ArgumentError.value(providerId, 'providerId');
    await _database.insert(
      'provider_settings',
      {
        'provider_id': providerId,
        'enabled': enabled ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool?> getProviderEnabled(String providerId) async {
    _ensureOpen();
    final rows = await _database.query(
      'provider_settings',
      columns: ['enabled'],
      where: 'provider_id = ?',
      whereArgs: [providerId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.single['enabled'] == 1;
  }

  Future<void> upsertCreatorProfile(CreatorProfile creator) async {
    _ensureOpen();
    await _database.transaction((tx) async {
      final row = {
        'id': creator.id,
        'name': creator.name,
        'aliases_json': jsonEncode(creator.aliases),
      };
      final found = await tx.query('creator_profiles', columns: ['id'], where: 'id = ?', whereArgs: [creator.id], limit: 1);
      if (found.isEmpty) {
        await tx.insert('creator_profiles', row);
      } else {
        await tx.update('creator_profiles', row, where: 'id = ?', whereArgs: [creator.id]);
      }
      for (final credit in creator.credits) {
        await tx.insert(
          'creator_credits',
          {
            'creator_id': creator.id,
            'work_id': credit.workId,
            'edition_id': credit.editionId,
            'provider_id': credit.providerId,
            'role': credit.role.name,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }


  Future<void> savePendingIdentityReview(PendingIdentityReview review) async {
    _ensureOpen();
    await _database.insert(
      'identity_review_queue',
      {
        'listing_key': review.key,
        'candidate_json': jsonEncode(_candidateMap(review.candidate)),
        'reason_json': jsonEncode(review.possibleMatches.map((decision) => {
          'verdict': decision.verdict.name,
          'score': decision.score,
          'evidence': decision.evidence,
        }).toList()),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PendingIdentityReview>> loadPendingIdentityReviews() async {
    _ensureOpen();
    final rows = await _database.query('identity_review_queue', orderBy: 'created_at ASC');
    final reviews = <PendingIdentityReview>[];
    for (final row in rows) {
      final candidate = _candidateFromJson(row['candidate_json'] as String);
      if (candidate == null) continue;
      final decoded = _tryDecode(row['reason_json'] as String);
      final decisions = <IdentityDecision>[];
      if (decoded is List) {
        for (final item in decoded.whereType<Map>()) {
          final verdictName = item['verdict'];
          final score = item['score'];
          final evidence = item['evidence'];
          if (verdictName is! String || score is! num || evidence is! List) continue;
          final verdict = IdentityVerdict.values.where((value) => value.name == verdictName);
          if (verdict.isEmpty) continue;
          decisions.add(IdentityDecision(
            verdict: verdict.first,
            score: score.toDouble(),
            evidence: evidence.whereType<String>().toList(growable: false),
          ));
        }
      }
      reviews.add(PendingIdentityReview(
        key: row['listing_key'] as String,
        candidate: candidate,
        possibleMatches: decisions,
      ));
    }
    return List.unmodifiable(reviews);
  }

  Future<void> deletePendingIdentityReview(String listingKey) async {
    _ensureOpen();
    await _database.delete('identity_review_queue', where: 'listing_key = ?', whereArgs: [listingKey]);
  }

  Future<CreatorProfile?> loadCreatorProfile(String creatorId) async {
    _ensureOpen();
    final profiles = await _database.query(
      'creator_profiles',
      where: 'id = ?',
      whereArgs: [creatorId],
      limit: 1,
    );
    if (profiles.isEmpty) return null;
    final rows = await _database.query('creator_credits', where: 'creator_id = ?', whereArgs: [creatorId]);
    final credits = <CreatorCredit>[];
    for (final row in rows) {
      credits.add(CreatorCredit(
        workId: row['work_id'] as String,
        editionId: row['edition_id'] as String?,
        providerId: row['provider_id'] as String?,
        role: _enumByName(CreatorRole.values, row['role'] as String, CreatorRole.other),
      ));
    }
    return CreatorProfile(
      id: profiles.single['id'] as String,
      name: profiles.single['name'] as String,
      aliases: _stringList(profiles.single['aliases_json']),
      credits: credits,
    );
  }

  static Map<String, Object?> _candidateMap(WorkCandidate candidate) => {
        'providerId': candidate.providerId,
        'externalId': candidate.externalId,
        'title': candidate.title,
        'providerUrl': candidate.providerUrl.toString(),
        'alternateTitles': candidate.alternateTitles,
        'creatorNames': candidate.creatorNames,
        'year': candidate.year,
        'format': candidate.format.name,
        'language': candidate.language,
        'description': candidate.description,
        'coverUrl': candidate.coverUrl?.toString(),
        'tags': candidate.tags,
      };

  static Object? _tryDecode(String encoded) {
    try {
      return jsonDecode(encoded);
    } on FormatException {
      return null;
    }
  }

  static WorkCandidate? _candidateFromJson(String encoded) {
    final decoded = _tryDecode(encoded);
    if (decoded is! Map) return null;
    final providerId = decoded['providerId'];
    final externalId = decoded['externalId'];
    final title = decoded['title'];
    final providerUrl = Uri.tryParse(
      decoded['providerUrl'] is String ? decoded['providerUrl'] as String : '',
    );
    if (providerId is! String || externalId is! String || title is! String ||
        providerUrl == null || !providerUrl.isAbsolute || providerUrl.host.isEmpty) {
      return null;
    }
    final coverValue = decoded['coverUrl'];
    final cover = coverValue is String ? Uri.tryParse(coverValue) : null;
    final yearValue = decoded['year'];
    return WorkCandidate(
      providerId: providerId,
      externalId: externalId,
      title: title,
      providerUrl: providerUrl,
      alternateTitles: decoded['alternateTitles'] is List
          ? (decoded['alternateTitles'] as List).whereType<String>().toList()
          : const [],
      creatorNames: decoded['creatorNames'] is List
          ? (decoded['creatorNames'] as List).whereType<String>().toList()
          : const [],
      year: yearValue is int ? yearValue : null,
      format: _enumByName(
        WorkFormat.values,
        decoded['format'] is String ? decoded['format'] as String : '',
        WorkFormat.unknown,
      ),
      language: decoded['language'] as String?,
      description: decoded['description'] as String?,
      coverUrl: cover != null && cover.isAbsolute ? cover : null,
      tags: decoded['tags'] is List ? (decoded['tags'] as List).whereType<String>().toList() : const [],
    );
  }

  Future<void> removeLibraryRecord(String workId, String editionId) async {
    _ensureOpen();
    await _database.delete(
      'library_entries',
      where: 'work_id = ? AND edition_id = ?',
      whereArgs: [workId, editionId],
    );
  }

  Future<void> touchCacheEntry(String key, {DateTime? accessedAt}) async {
    _ensureOpen();
    await _database.update(
      'cache_entries',
      {'last_accessed_at': (accessedAt ?? DateTime.now()).millisecondsSinceEpoch},
      where: 'cache_key = ?',
      whereArgs: [key],
    );
  }

  Future<Map<String, Object?>?> loadVoicePackInstall(String packId) async {
    _ensureOpen();
    final rows = await _database.query('voice_pack_installs', where: 'pack_id = ?', whereArgs: [packId], limit: 1);
    return rows.isEmpty ? null : Map.unmodifiable(rows.single);
  }

  Future<void> removeVoicePackInstall(String packId) async {
    _ensureOpen();
    await _database.delete('voice_pack_installs', where: 'pack_id = ?', whereArgs: [packId]);
  }

  Future<void> saveCacheEntry(CacheEntryFile entry) async {
    _ensureOpen();
    await _database.insert(
      'cache_entries',
      {
        'cache_key': entry.entry.key,
        'bucket': entry.entry.bucket.name,
        'bytes': entry.entry.bytes,
        'file_path': entry.filePath,
        'last_accessed_at': entry.entry.lastAccessedAt.millisecondsSinceEpoch,
        'pinned': entry.entry.pinned ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Atomically updates cache metadata after the filesystem layer has staged its
  /// incoming file and selected evictions. User-owned library/progress rows are
  /// deliberately outside this transaction.
  Future<void> commitCacheWrite(
    CacheEntryFile entry, {
    Iterable<String> evictedKeys = const [],
  }) async {
    _ensureOpen();
    await _database.transaction((tx) async {
      for (final key in evictedKeys.toSet()) {
        if (key == entry.entry.key) continue;
        await tx.delete('cache_entries', where: 'cache_key = ?', whereArgs: [key]);
      }
      await tx.insert(
        'cache_entries',
        {
          'cache_key': entry.entry.key,
          'bucket': entry.entry.bucket.name,
          'bytes': entry.entry.bytes,
          'file_path': entry.filePath,
          'last_accessed_at': entry.entry.lastAccessedAt.millisecondsSinceEpoch,
          'pinned': entry.entry.pinned ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<CacheEntryFile>> loadCacheEntries() async {
    _ensureOpen();
    final rows = await _database.query('cache_entries');
    return List.unmodifiable(rows.map((row) => CacheEntryFile(
      entry: CacheEntry(
        key: row['cache_key'] as String,
        bucket: _enumByName(CacheBucket.values, row['bucket'] as String, CacheBucket.other),
        bytes: row['bytes'] as int,
        lastAccessedAt: DateTime.fromMillisecondsSinceEpoch(row['last_accessed_at'] as int),
        pinned: (row['pinned'] as int? ?? 0) == 1,
      ),
      filePath: row['file_path'] as String,
    )));
  }

  Future<CacheEntryFile?> findCacheEntry(String key) async {
    _ensureOpen();
    final entries = await loadCacheEntries();
    for (final entry in entries) {
      if (entry.entry.key == key) return entry;
    }
    return null;
  }

  Future<CacheWritePlan> planCacheWrite({
    required int incomingBytes,
    StorageBudget? budget,
    String? replacingKey,
  }) async {
    _ensureOpen();
    final entries = await loadCacheEntries();
    final effectiveEntries = replacingKey == null
        ? entries
        : entries.where((item) => item.entry.key != replacingKey).toList(growable: false);
    final plan = (budget ?? StorageBudget()).plan(
      currentEntries: effectiveEntries.map((item) => item.entry),
      incomingBytes: incomingBytes,
    );
    final keys = plan.evictKeys.toSet();
    return CacheWritePlan(
      storagePlan: plan,
      filesToEvict: List.unmodifiable(
        effectiveEntries.where((item) => keys.contains(item.entry.key)).map((item) => item.filePath),
      ),
    );
  }

  /// Call this only after the caller has removed the corresponding files successfully.
  Future<void> confirmCacheEviction(Iterable<String> keys) async {
    _ensureOpen();
    await _database.transaction((tx) async {
      for (final key in keys) {
        await tx.delete('cache_entries', where: 'cache_key = ?', whereArgs: [key]);
      }
    });
  }

  Future<void> recordVoicePackInstall({
    required String packId,
    required String version,
    required String locale,
    required String licenseId,
    required String sha256,
    required String installPath,
  }) async {
    _ensureOpen();
    if (packId.trim().isEmpty || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
      throw ArgumentError('Voice pack install requires a valid id and SHA-256 digest.');
    }
    await _database.insert(
      'voice_pack_installs',
      {
        'pack_id': packId,
        'version': version,
        'locale': locale,
        'license_id': licenseId,
        'sha256': sha256.toLowerCase(),
        'install_path': installPath,
        'installed_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _database.close();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('KurotoonDatabase is closed.');
  }

  static WorkCandidate? _candidateFromRow(Map<String, Object?> row) {
    final providerUrl = Uri.tryParse(row['provider_url'] as String? ?? '');
    if (providerUrl == null || !providerUrl.isAbsolute || providerUrl.host.isEmpty) return null;
    final coverText = row['cover_url'] as String?;
    final coverUrl = coverText == null ? null : Uri.tryParse(coverText);
    return WorkCandidate(
      providerId: row['provider_id'] as String,
      externalId: row['external_id'] as String,
      title: row['title'] as String,
      providerUrl: providerUrl,
      alternateTitles: _stringList(row['alternate_titles_json']),
      creatorNames: _stringList(row['creator_names_json']),
      year: row['year'] as int?,
      format: _enumByName(WorkFormat.values, row['format'] as String, WorkFormat.unknown),
      language: row['language'] as String?,
      description: row['description'] as String?,
      coverUrl: coverUrl != null && coverUrl.isAbsolute ? coverUrl : null,
      tags: _stringList(row['tags_json']),
    );
  }

  static ReadingProgress _progressFromRow(Map<String, Object?> row) => ReadingProgress(
        workId: row['work_id'] as String,
        editionId: row['edition_id'] as String,
        chapterId: row['chapter_id'] as String,
        anchor: row['anchor'] as String?,
        fraction: (row['fraction'] as num).toDouble(),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int, isUtc: true),
        deviceId: row['device_id'] as String,
        revision: row['revision'] as int,
      );

  static DateTime? _dateFromMillis(int? value) =>
      value == null ? null : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

  static List<String> _stringList(Object? encoded) {
    if (encoded is! String) return const [];
    try {
      final decoded = jsonDecode(encoded);
      return decoded is List ? decoded.whereType<String>().toList(growable: false) : const [];
    } on FormatException {
      return const [];
    }
  }

  static T _enumByName<T extends Enum>(List<T> values, String name, T fallback) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
