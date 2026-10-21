import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:kurotoon_flutter/services/catalog_workflow_service.dart';
import 'package:kurotoon_flutter/storage/kurotoon_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeSource implements SourceProvider, SeriesProvider, ChapterFeedProvider, ReaderPagesProvider {
  _FakeSource({required this.searchResult});

  final WorkCandidate searchResult;

  @override
  final ProviderDescriptor descriptor = ProviderDescriptor(
    id: 'fake.source',
    name: 'Fake source for integration tests',
    homepage: Uri(scheme: 'https', host: 'fake.example.org'),
    capabilities: {
      ProviderCapability.search,
      ProviderCapability.series,
      ProviderCapability.chapters,
      ProviderCapability.pages,
    },
    enabledByDefault: true,
  );

  @override
  Future<ProviderResponse<List<WorkCandidate>>> search(
    String query, {
    required CancellationToken cancellationToken,
  }) async {
    cancellationToken.throwIfCancelled();
    return ProviderResponse(status: ProviderResultStatus.success, data: [searchResult]);
  }

  @override
  Future<ProviderResponse<WorkCandidate>> getSeries(
    String seriesId, {
    required CancellationToken cancellationToken,
  }) async {
    cancellationToken.throwIfCancelled();
    if (seriesId != searchResult.externalId) {
      return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Unexpected series ID');
    }
    return ProviderResponse(
      status: ProviderResultStatus.success,
      data: WorkCandidate(
        providerId: descriptor.id,
        externalId: searchResult.externalId,
        title: 'Blue Star: Updated Edition',
        alternateTitles: const ['The Blue Star'],
        creatorNames: const ['Artist', 'Writer'],
        year: 2023,
        format: WorkFormat.manga,
        providerUrl: searchResult.providerUrl,
        description: 'Refreshed synopsis',
        coverUrl: searchResult.coverUrl,
      ),
    );
  }

  @override
  Future<ProviderResponse<List<ChapterUnit>>> getChapters(
    String seriesId, {
    required CancellationToken cancellationToken,
    List<String> translatedLanguages = const ['en'],
    int limit = 100,
    int offset = 0,
  }) async {
    cancellationToken.throwIfCancelled();
    if (seriesId != searchResult.externalId || offset != 0) {
      return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Unexpected chapter request');
    }
    return ProviderResponse(
      status: ProviderResultStatus.success,
      data: [
        ChapterUnit(
          id: 'source-chapter-1',
          editionId: 'untrusted-provider-edition-id',
          title: 'The Beginning',
          chapterNumber: 1,
          kind: ChapterKind.regular,
          listings: [
            ChapterListing(
              providerId: descriptor.id,
              externalId: 'chapter-1',
              url: Uri.https('fake.example.org', '/chapter/chapter-1'),
              languageCode: 'en',
              publishedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<ProviderResponse<ReaderPageManifest>> getPages(
    String chapterId, {
    required CancellationToken cancellationToken,
    bool dataSaver = false,
  }) async {
    cancellationToken.throwIfCancelled();
    if (chapterId != 'chapter-1') {
      return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Unexpected chapter ID');
    }
    return ProviderResponse(
      status: ProviderResultStatus.success,
      data: ReaderPageManifest(
        chapterId: chapterId,
        baseUrl: Uri.https('cdn.fake.example.org', '/chapter'),
        hash: 'manifest-hash',
        normalFilenames: const ['001.webp', '002.webp'],
        dataSaverFilenames: const ['001.webp'],
      ),
    );
  }
}

class _HangingSeriesSource extends _FakeSource {
  _HangingSeriesSource({required super.searchResult});

  @override
  Future<ProviderResponse<WorkCandidate>> getSeries(
    String seriesId, {
    required CancellationToken cancellationToken,
  }) =>
      Completer<ProviderResponse<WorkCandidate>>().future;
}

WorkCandidate _candidate() => WorkCandidate(
      providerId: 'fake.source',
      externalId: 'series-1',
      title: 'Blue Star',
      creatorNames: const ['Artist'],
      year: 2023,
      format: WorkFormat.manga,
      providerUrl: Uri.https('fake.example.org', '/series/series-1'),
      coverUrl: Uri.https('cdn.fake.example.org', '/cover.webp'),
    );

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory temp;
  late KurotoonDatabase database;
  late ProviderRegistry providers;
  late CatalogWorkflowService workflow;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kurotoon-catalog-workflow-test-');
    database = await KurotoonDatabase.open(
      databasePath: p.join(temp.path, 'kurotoon.db'),
      factory: databaseFactoryFfi,
    );
    providers = ProviderRegistry()..register(_FakeSource(searchResult: _candidate()));
    workflow = CatalogWorkflowService(
      providers: providers,
      database: database,
      deviceId: 'test-device',
      clock: () => DateTime.utc(2026, 10, 19, 12),
    );
  });

  tearDown(() async {
    await workflow.dispose();
    providers.dispose();
    await database.close();
    await temp.delete(recursive: true);
  });

  test('unified search keeps the latest aggregate for a canonical work', () {
    final first = _candidate();
    final second = WorkCandidate(
      providerId: 'other.source',
      externalId: 'series-2',
      title: 'Blue Star',
      creatorNames: const ['Artist'],
      year: 2023,
      format: WorkFormat.manga,
      providerUrl: Uri.https('other.fake.example.org', '/series/series-2'),
    );
    final work = WorkRecord(
      id: 'work/blue-star',
      title: 'Blue Star',
      creatorNames: const ['Artist'],
      year: 2023,
      format: WorkFormat.manga,
    );
    final firstEntry = CatalogEntry(work: work, listings: [first]);
    final mergedEntry = CatalogEntry(work: work, listings: [first, second]);
    final outcome = CatalogSearchOutcome(
      batch: SearchBatch(results: const [], cancelled: false),
      catalogResults: [
        CatalogUpsertResult(status: CatalogUpsertStatus.created, entry: firstEntry),
        CatalogUpsertResult(status: CatalogUpsertStatus.linked, entry: mergedEntry),
      ],
    );

    expect(outcome.entries, hasLength(1));
    expect(outcome.entries.single.listings, hasLength(2));
    expect(outcome.entries.single.providerIds, containsAll(['fake.source', 'other.source']));
  });

  test('search, refresh metadata, save chapter feed, fetch fresh pages, and persist progress', () async {
    final firstSearch = await workflow.searchAndCatalog('Blue Star');
    expect(firstSearch.batch.candidates, hasLength(1));
    expect(firstSearch.catalogResults.single.status, CatalogUpsertStatus.created);
    expect((await database.loadCatalog()), hasLength(1));

    final workId = firstSearch.entries.single.work.id;
    final refreshed = await workflow.refreshSeries(workId: workId, providerId: 'fake.source');
    expect(refreshed.status, ProviderResultStatus.success);
    expect((await database.loadCatalog()).single.work.title, 'Blue Star');
    expect((await database.loadCatalog()).single.listings.single.description, 'Refreshed synopsis');
    expect((await database.loadCatalog()).single.work.alternateTitles, contains('Blue Star: Updated Edition'));

    final fetched = await workflow.fetchAndStoreChapters(
      workId: workId,
      providerId: 'fake.source',
      translatedLanguages: const ['en'],
    );
    expect(fetched.status, ProviderResultStatus.success);
    expect(fetched.data, hasLength(1));
    final chapter = fetched.data!.single;
    expect(chapter.id, 'chapter/fake.source/chapter-1');
    expect(chapter.editionId, 'edition/fake.source/series-1/en');
    expect((await database.loadEdition(chapter.editionId))!.workId, workId);

    final pages = await workflow.fetchReaderPages(
      workId: workId,
      editionId: chapter.editionId,
      chapterId: chapter.id,
    );
    expect(pages.status, ProviderResultStatus.success);
    expect(pages.data!.urls(), hasLength(2));
    expect(pages.data!.urls().first.host, 'cdn.fake.example.org');

    final libraryRecord = await workflow.addToLibrary(
      workId: workId,
      editionId: chapter.editionId,
      status: LibraryStatus.reading,
    );
    expect(libraryRecord.status, LibraryStatus.reading);
    final progress = await workflow.saveProgress(
      workId: workId,
      editionId: chapter.editionId,
      chapterId: chapter.id,
      fraction: 0.4,
      anchor: 'page:1',
    );
    expect(progress.deviceId, 'test-device');
    expect((await workflow.loadProgress(workId, chapter.editionId))!.fraction, 0.4);

    // A second search rehydrates the catalog and must not create a second work.
    final secondSearch = await workflow.searchAndCatalog('Blue Star');
    expect(secondSearch.catalogResults.single.status, CatalogUpsertStatus.alreadyKnown);
    expect((await database.loadCatalog()), hasLength(1));
  });

  test('refuses progress against a chapter from another edition', () async {
    final outcome = await workflow.searchAndCatalog('Blue Star');
    final workId = outcome.entries.single.work.id;
    await workflow.fetchAndStoreChapters(workId: workId, providerId: 'fake.source');
    await expectLater(
      workflow.saveProgress(
        workId: workId,
        editionId: 'edition/fake.source/series-1/en',
        chapterId: 'chapter/fake.source/not-installed',
        fraction: 0.5,
      ),
      throwsArgumentError,
    );
  }); 
  test('bounds source detail calls that ignore cancellation', () async {
    await workflow.dispose();
    providers.dispose();

    providers = ProviderRegistry()..register(_HangingSeriesSource(searchResult: _candidate()));
    workflow = CatalogWorkflowService(
      providers: providers,
      database: database,
      deviceId: 'test-device',
      providerTimeout: const Duration(milliseconds: 60),
      clock: () => DateTime.utc(2026, 10, 19, 12),
    );

    final outcome = await workflow.searchAndCatalog('Blue Star');
    final response = await workflow.refreshSeries(
      workId: outcome.entries.single.work.id,
      providerId: 'fake.source',
    );
    expect(response.status, ProviderResultStatus.timedOut);
  });

}
