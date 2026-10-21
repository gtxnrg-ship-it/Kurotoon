import 'dart:io';

import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:kurotoon_flutter/storage/kurotoon_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory temp;
  late KurotoonDatabase database;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kurotoon-storage-test-');
    database = await KurotoonDatabase.open(
      databasePath: p.join(temp.path, 'test.db'),
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  WorkCandidate candidate() => WorkCandidate(
        providerId: 'mangadex',
        externalId: 'series-1',
        title: 'Blue Star',
        alternateTitles: const ['The Blue Star'],
        creatorNames: const ['A. Artist'],
        year: 2023,
        format: WorkFormat.manga,
        providerUrl: Uri.parse('https://mangadex.org/title/series-1'),
        coverUrl: Uri.parse('https://uploads.mangadex.org/cover.jpg'),
        tags: const ['Fantasy'],
      );

  CatalogEntry entry() => CatalogEntry(
        work: WorkRecord(
          id: 'work/blue-star',
          title: 'Blue Star',
          alternateTitles: const ['The Blue Star'],
          creatorNames: const ['A. Artist'],
          year: 2023,
          format: WorkFormat.manga,
        ),
        listings: [candidate()],
        verified: true,
      );

  test('persists catalog identity and source provenance across reopen', () async {
    await database.upsertCatalogEntry(entry());
    final loaded = await database.loadCatalog();
    expect(loaded, hasLength(1));
    expect(loaded.single.work.id, 'work/blue-star');
    expect(loaded.single.work.title, 'Blue Star');
    expect(loaded.single.verified, isTrue);
    expect(loaded.single.listings.single.listingKey, 'mangadex:series-1');
    expect(loaded.single.listings.single.tags, contains('Fantasy'));

    await database.close();
    database = await KurotoonDatabase.open(
      databasePath: p.join(temp.path, 'test.db'),
      factory: databaseFactoryFfi,
    );
    expect((await database.loadCatalog()).single.listings.single.providerUrl.host, 'mangadex.org');
    final restoredMatch = await database.loadCatalogCandidatesForMatching(WorkCandidate(
      providerId: 'community-source',
      externalId: 'blue-star-translation',
      title: 'The Blue Star',
      creatorNames: const ['A. Artist'],
      providerUrl: Uri.parse('https://community.example.org/blue-star'),
    ));
    expect(restoredMatch.entries.map((entry) => entry.work.id), contains('work/blue-star'));
    expect(restoredMatch.hasMore, isFalse);
  });

  test('indexes creator profiles and returns bounded, title-sorted work pages', () async {
    await database.upsertCatalogEntry(entry());
    await database.upsertCatalogEntry(CatalogEntry(
      work: WorkRecord(
        id: 'work/red-moon',
        title: 'Red Moon',
        creatorNames: const ['A. Artist'],
        format: WorkFormat.manga,
      ),
      listings: [WorkCandidate(
        providerId: 'mangadex',
        externalId: 'red-moon',
        title: 'Red Moon',
        creatorNames: const ['A. Artist'],
        format: WorkFormat.manga,
        providerUrl: Uri.parse('https://mangadex.org/title/red-moon'),
      )],
    ));

    final creators = await database.searchCreatorProfiles('A. Art');
    expect(creators, hasLength(1));
    final creator = creators.single;
    final firstPage = await database.loadCreatorWorks(creator.id, limit: 1);
    final secondPage = await database.loadCreatorWorks(creator.id, limit: 1, offset: 1);
    expect(firstPage, hasLength(1));
    expect(secondPage, hasLength(1));
    expect(firstPage.single.work.title, 'Blue Star');
    expect(secondPage.single.work.title, 'Red Moon');

    await database.upsertCatalogEntry(entry());
    final profile = await database.loadCreatorProfile(creator.id);
    expect(profile!.credits, hasLength(2));
    expect(profile.credits.map((credit) => credit.workId).toSet(), containsAll(['work/blue-star', 'work/red-moon']));
  });

  test('stores edition chapters and the user library independently', () async {
    await database.upsertCatalogEntry(entry());
    await database.upsertEdition(EditionRecord(
      id: 'edition-en',
      workId: 'work/blue-star',
      format: WorkFormat.manga,
      languageCode: 'en',
      isOfficial: false,
    ));
    await database.upsertChapter(ChapterUnit(
      id: 'chapter-1',
      editionId: 'edition-en',
      kind: ChapterKind.regular,
      chapterNumber: 1,
      title: 'Opening',
      listings: [
        ChapterListing(
          providerId: 'mangadex',
          externalId: 'chapter-1',
          url: Uri.parse('https://mangadex.org/chapter/chapter-1'),
          languageCode: 'en',
          publishedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    ));
    await database.putLibraryRecord(LibraryRecord(
      workId: 'work/blue-star',
      editionId: 'edition-en',
      status: LibraryStatus.reading,
      addedAt: DateTime.utc(2026, 1, 1),
      sortOrder: 10,
    ));

    final chapters = await database.loadChapters('edition-en');
    expect(chapters, hasLength(1));
    expect(chapters.single.title, 'Opening');
    expect(chapters.single.listings.single.languageCode, 'en');
    expect((await database.loadLibrary()).single.status, LibraryStatus.reading);
    expect((await database.loadLibrary(status: LibraryStatus.completed)), isEmpty);
  });

  test('progress sync cannot replace newer progress with stale state', () async {
    final now = DateTime.utc(2026, 5, 1);
    final newer = ReadingProgress(
      workId: 'work',
      editionId: 'edition',
      chapterId: 'chapter-8',
      fraction: 0.25,
      updatedAt: now,
      deviceId: 'phone',
      revision: 2,
    );
    final stale = ReadingProgress(
      workId: 'work',
      editionId: 'edition',
      chapterId: 'chapter-2',
      fraction: 1,
      updatedAt: now.subtract(const Duration(days: 1)),
      deviceId: 'tablet',
      revision: 100,
    );
    await database.saveProgress(newer);
    final saved = await database.saveProgress(stale);
    expect(saved.chapterId, 'chapter-8');
    expect((await database.loadProgress('work', 'edition'))!.fraction, 0.25);
  });

  test('persists settings and provider switches as typed values', () async {
    await database.setSetting('galaxy.motion', true);
    await database.setSetting('reader.voicePack', 'voice-en');
    await database.setProviderEnabled('mangadex', false);
    expect(await database.getSetting<bool>('galaxy.motion'), isTrue);
    expect(await database.getSetting<String>('reader.voicePack'), 'voice-en');
    expect(await database.getProviderEnabled('mangadex'), isFalse);
    expect(await database.getProviderEnabled('other'), isNull);
  });

  test('plans cache eviction before removing metadata and never deletes pinned files', () async {
    final now = DateTime.utc(2026, 1, 1);
    await database.saveCacheEntry(CacheEntryFile(
      entry: CacheEntry(
        key: 'provider-response',
        bucket: CacheBucket.providerResponse,
        bytes: 40,
        lastAccessedAt: now,
      ),
      filePath: p.join(temp.path, 'provider.json'),
    ));
    await database.saveCacheEntry(CacheEntryFile(
      entry: CacheEntry(
        key: 'offline-page',
        bucket: CacheBucket.page,
        bytes: 80,
        lastAccessedAt: now,
        pinned: true,
      ),
      filePath: p.join(temp.path, 'offline.webp'),
    ));
    final plan = await database.planCacheWrite(incomingBytes: 30, budget: StorageBudget(maxBytes: 100));
    expect(plan.storagePlan.accepted, isFalse);
    expect(plan.filesToEvict, isEmpty);
    expect((await database.loadCacheEntries()), hasLength(2));
  });

  test('persists repositories and keeps their installed extensions tied to provenance', () async {
    final repository = ExtensionRepository(
      id: 'org.example.repository',
      name: 'Example Repository',
      indexUri: Uri.parse('https://raw.example.org/repo/index.min.json'),
    );
    await database.saveExtensionRepository(repository);
    final entry = ExtensionPackageEntry(
      id: 'org.example.source',
      name: 'Example Source',
      version: '1.0.0',
      manifestUri: Uri.parse('https://raw.example.org/repo/source.json'),
      sha256: List.filled(64, 'a').join(),
      sizeBytes: 10,
      minimumAppApi: 1,
      capabilities: const {ExtensionCapability.search},
    );
    await database.recordInstalledExtension(
      entry: entry,
      repositoryId: repository.id,
      installPath: p.join(temp.path, 'extensions', 'source.json'),
    );
    expect((await database.loadExtensionRepositories()).single['index_url'], repository.indexUri.toString());
    expect((await database.loadInstalledExtensions()).single['repository_id'], repository.id);
    await database.setExtensionEnabled(entry.id, true);
    expect((await database.loadInstalledExtensions()).single['enabled'], 1);
    await expectLater(database.removeExtensionRepository(repository.id), throwsStateError);
    await database.removeInstalledExtension(entry.id);
    await database.removeExtensionRepository(repository.id);
    expect(await database.loadExtensionRepositories(), isEmpty);
  });


  test('repository refresh preserves its identity but cannot silently change its URL', () async {
    final repository = ExtensionRepository(
      id: 'org.example.repository',
      name: 'Example Repository',
      indexUri: Uri.parse('https://raw.example.org/repo/index.min.json'),
    );
    await database.saveExtensionRepository(repository);
    await database.saveExtensionRepository(repository, indexDigest: List.filled(64, 'a').join());
    expect((await database.loadExtensionRepositories()).single['last_index_digest'], List.filled(64, 'a').join());

    await expectLater(
      database.saveExtensionRepository(ExtensionRepository(
        id: repository.id,
        name: repository.name,
        indexUri: Uri.parse('https://different.example.org/index.json'),
      )),
      throwsStateError,
    );
    expect((await database.loadExtensionRepositories()).single['index_url'], repository.indexUri.toString());
  });



  test('rejects a library row that pairs a work with another work edition', () async {
    await database.upsertCatalogEntry(entry());
    await database.upsertCatalogEntry(CatalogEntry(
      work: WorkRecord(
        id: 'work/other',
        title: 'Other Work',
        format: WorkFormat.manga,
      ),
      listings: [
        WorkCandidate(
          providerId: 'mangadex',
          externalId: 'series-2',
          title: 'Other Work',
          providerUrl: Uri.parse('https://mangadex.org/title/series-2'),
          format: WorkFormat.manga,
        ),
      ],
    ));
    await database.upsertEdition(EditionRecord(
      id: 'edition-en',
      workId: 'work/blue-star',
      format: WorkFormat.manga,
      languageCode: 'en',
    ));

    await expectLater(
      database.putLibraryRecord(LibraryRecord(
        workId: 'work/other',
        editionId: 'edition-en',
        status: LibraryStatus.reading,
        addedAt: DateTime.utc(2026, 1, 1),
        sortOrder: 0,
      )),
      throwsStateError,
    );
    expect(await database.loadLibrary(), isEmpty);
  });



  test('protects the bundled official repository from removal', () async {
    final repository = ExtensionRepository(
      id: 'org.kurotoon.official',
      name: 'KuroToon Official Starter Repository',
      indexUri: Uri.parse(
        'https://raw.githubusercontent.com/gtxnrg-ship-it/Kurotoon/main/catalog/official/index.json',
      ),
      trust: RepositoryTrust.builtIn,
    );
    await database.saveExtensionRepository(repository);

    await expectLater(
      database.removeExtensionRepository(repository.id),
      throwsStateError,
    );
    expect(
      (await database.loadExtensionRepositories()).single['trust'],
      RepositoryTrust.builtIn.name,
    );
  });
  test('pages large catalogs with a stable cursor and bounded search results', () async {
    for (var i = 0; i < 120; i++) {
      final suffix = i.toString().padLeft(3, '0');
      final title = 'Series $suffix';
      await database.upsertCatalogEntry(CatalogEntry(
        work: WorkRecord(
          id: 'work/series-$suffix',
          title: title,
          alternateTitles: ['Alias $suffix'],
          creatorNames: ['Creator $suffix'],
          format: WorkFormat.manga,
        ),
        listings: [WorkCandidate(
          providerId: 'test.source',
          externalId: 'series-$suffix',
          title: title,
          providerUrl: Uri.parse('https://source.example.org/series/$suffix'),
        )],
      ));
    }

    final firstPage = await database.loadCatalogPage(limit: 30);
    expect(firstPage, hasLength(30));
    expect(firstPage.first.work.title, 'Series 000');
    expect(firstPage.last.work.title, 'Series 029');
    expect(firstPage.first.listings, hasLength(1));

    final secondPage = await database.loadCatalogPage(
      limit: 30,
      afterTitle: firstPage.last.work.title,
      afterId: firstPage.last.work.id,
    );
    expect(secondPage, hasLength(30));
    expect(secondPage.first.work.title, 'Series 030');
    expect(secondPage.map((entry) => entry.work.id).toSet().intersection(
      firstPage.map((entry) => entry.work.id).toSet(),
    ), isEmpty);

    final matchPage = await database.loadCatalogCandidatesForMatching(
      WorkCandidate(
        providerId: 'another.source',
        externalId: 'series-090',
        title: 'Series 090',
        creatorNames: const ['Creator 090'],
        providerUrl: Uri.parse('https://another.example.org/series/090'),
      ),
    );
    expect(matchPage.hasMore, isFalse);
    expect(matchPage.entries.map((entry) => entry.work.title), contains('Series 090'));

    final broadMatchPage = await database.loadCatalogCandidatesForMatching(
      WorkCandidate(
        providerId: 'another.source',
        externalId: 'new-series',
        title: 'Series',
        providerUrl: Uri.parse('https://another.example.org/series'),
      ),
      maxCandidates: 10,
    );
    expect(broadMatchPage.entries, hasLength(10));
    expect(broadMatchPage.hasMore, isTrue);

    final search = await database.loadCatalogPage(query: 'Series 09', limit: 20);
    expect(search, hasLength(10));
    expect(search.first.work.title, 'Series 090');
    expect(search.last.work.title, 'Series 099');
    expect(await database.loadCatalogPage(query: 'Series 09%', limit: 20), isEmpty);
    await expectLater(database.loadCatalogPage(limit: 101), throwsArgumentError);
  });



  test('shop purchase atomically charges currency and grants one collectible', () async {
    await database.setSetting('shop.wallet.silver.v1', 250);
    await database.setSetting('shop.collection.owned.v1', <String>['kuru_happy']);
    final result = await database.purchaseShopCollectible(
      itemId: 'kuru_love',
      price: 100,
      useGold: false,
    );
    expect(result, ShopPurchaseStatus.purchased);
    expect(await database.getSetting<int>('shop.wallet.silver.v1'), 150);
    expect(await database.getSetting<List<dynamic>>('shop.collection.owned.v1'),
        containsAll(['kuru_happy', 'kuru_love']));
  });

  test('shop purchase cannot charge twice for an already-owned collectible', () async {
    await database.setSetting('shop.wallet.silver.v1', 250);
    await database.setSetting('shop.collection.owned.v1', <String>['kuru_love']);
    final result = await database.purchaseShopCollectible(
      itemId: 'kuru_love',
      price: 100,
      useGold: false,
    );
    expect(result, ShopPurchaseStatus.alreadyOwned);
    expect(await database.getSetting<int>('shop.wallet.silver.v1'), 250);
  });

  test('shop purchase with insufficient funds changes neither wallet nor ownership', () async {
    await database.setSetting('shop.wallet.gold.v1', 2);
    await database.setSetting('shop.collection.owned.v1', <String>['kuru_happy']);
    final result = await database.purchaseShopCollectible(
      itemId: 'kuru_legendary',
      price: 10,
      useGold: true,
    );
    expect(result, ShopPurchaseStatus.insufficientFunds);
    expect(await database.getSetting<int>('shop.wallet.gold.v1'), 2);
    expect(await database.getSetting<List<dynamic>>('shop.collection.owned.v1'),
        ['kuru_happy']);
  });

}
