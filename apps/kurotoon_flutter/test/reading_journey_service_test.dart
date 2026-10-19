import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:kurotoon_flutter/services/reading_journey_service.dart';
import 'package:kurotoon_flutter/storage/kurotoon_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeProvider
    implements SourceProvider, SeriesProvider, ChapterFeedProvider, ReaderPagesProvider {
  _FakeProvider(this._id);

  final String _id;
  int pageRequests = 0;

  @override
  ProviderDescriptor get descriptor => ProviderDescriptor(
        id: _id,
        name: 'Fake catalog',
        homepage: Uri.parse('https://catalog.example.org'),
        capabilities: const {
          ProviderCapability.search,
          ProviderCapability.series,
          ProviderCapability.chapters,
          ProviderCapability.pages,
        },
        isBuiltIn: true,
        enabledByDefault: true,
      );

  WorkCandidate _candidate({String id = 'series-1'}) => WorkCandidate(
        providerId: _id,
        externalId: id,
        title: 'Blue Star',
        alternateTitles: const ['The Blue Star'],
        creatorNames: const ['A. Artist'],
        year: 2023,
        format: WorkFormat.manga,
        providerUrl: Uri.parse('https://catalog.example.org/title/' + id),
        coverUrl: Uri.parse('https://catalog.example.org/covers/' + id + '.jpg'),
        description: 'A test synopsis',
        tags: const ['Fantasy'],
      );

  @override
  Future<ProviderResponse<List<WorkCandidate>>> search(
    String query, {
    required CancellationToken cancellationToken,
  }) async {
    cancellationToken.throwIfCancelled();
    return ProviderResponse(status: ProviderResultStatus.success, data: [_candidate()]);
  }

  @override
  Future<ProviderResponse<WorkCandidate>> getSeries(
    String seriesId, {
    required CancellationToken cancellationToken,
  }) async {
    cancellationToken.throwIfCancelled();
    return ProviderResponse(status: ProviderResultStatus.success, data: _candidate(id: seriesId));
  }

  ChapterUnit _chapter(int number) => ChapterUnit(
        id: 'remote-$number',
        editionId: 'untrusted-remote-edition',
        chapterNumber: number.toDouble(),
        title: 'Chapter ' + number.toString(),
        kind: ChapterKind.regular,
        listings: [
          ChapterListing(
            providerId: _id,
            externalId: 'chapter-$number',
            url: Uri.parse('https://catalog.example.org/chapter/chapter-$number'),
            languageCode: 'en',
            publishedAt: DateTime.utc(2026, 1, number),
          ),
        ],
      );

  @override
  Future<ProviderResponse<List<ChapterUnit>>> getChapters(
    String seriesId, {
    required CancellationToken cancellationToken,
    List<String> translatedLanguages = const ['en'],
    int limit = 100,
    int offset = 0,
  }) async {
    cancellationToken.throwIfCancelled();
    pageRequests++;
    final all = [_chapter(1), _chapter(2)];
    final page = all.skip(offset).take(limit).toList();
    return ProviderResponse(
      status: ProviderResultStatus.success,
      data: page,
      message: offset == 0 && page.length == limit ? 'More chapters are available' : null,
    );
  }

  @override
  Future<ProviderResponse<ReaderPageManifest>> getPages(
    String chapterId, {
    required CancellationToken cancellationToken,
    bool dataSaver = false,
  }) async {
    cancellationToken.throwIfCancelled();
    return ProviderResponse(
      status: ProviderResultStatus.success,
      data: ReaderPageManifest(
        chapterId: chapterId,
        baseUrl: Uri.parse('https://cdn.example.org'),
        hash: 'page-hash',
        normalFilenames: const ['01.jpg', '02.jpg'],
        dataSaverFilenames: const ['01.jpg'],
      ),
    );
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory temp;
  late KurotoonDatabase database;
  late _FakeProvider provider;
  late ReadingJourneyService journey;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kurotoon-reading-journey-test-');
    database = await KurotoonDatabase.open(
      databasePath: p.join(temp.path, 'journey.db'),
      factory: databaseFactoryFfi,
    );
    provider = _FakeProvider('fake-source');
    final registry = ProviderRegistry()..register(provider);
    journey = ReadingJourneyService(
      providers: registry,
      database: database,
      defaultChapterPageSize: 2,
      deviceIdProvider: () async => 'test-device',
    );
  });

  tearDown(() async {
    journey.dispose();
    await database.close();
    await temp.delete(recursive: true);
  });

  test('search, series identity, chapter pagination, fresh pages and progress resume connect', () async {
    final search = await journey.search('Blue Star');
    expect(search.candidates, hasLength(1));

    final opened = await journey.openSeries(search.candidates.single);
    expect(opened.detailsRefreshed, isTrue);
    expect(opened.catalogResult.status, CatalogUpsertStatus.created);
    final workId = opened.catalogResult.entry!.work.id;

    final firstPage = await journey.refreshChapters(
      workId: workId,
      providerId: 'fake-source',
      limit: 2,
      offset: 0,
    );
    expect(firstPage.chapters, hasLength(2));
    expect(firstPage.hasMore, isTrue);
    expect(firstPage.editionIds, hasLength(1));

    final secondPage = await journey.refreshChapters(
      workId: workId,
      providerId: 'fake-source',
      limit: 2,
      offset: firstPage.nextOffset!,
    );
    expect(secondPage.chapters, isEmpty);
    expect(secondPage.hasMore, isFalse);

    final editionId = firstPage.editionIds.single;
    final stored = await journey.loadStoredChapters(editionId);
    expect(stored, hasLength(2));
    expect(stored.first.id, isNot('remote-1'));
    expect(stored.first.listings.single.externalId, 'chapter-1');

    final manifest = await journey.loadReaderPages(stored.first, dataSaver: true);
    expect(manifest.chapterId, 'chapter-1');
    expect(manifest.urls(dataSaver: true).single.toString(),
        'https://cdn.example.org/data-saver/page-hash/01.jpg');

    final libraryRecord = await journey.addToLibrary(
      workId: workId,
      providerId: 'fake-source',
      languageCode: 'en',
      status: LibraryStatus.reading,
    );
    expect(libraryRecord.editionId, editionId);

    final progress = await journey.saveReadingProgress(
      workId: workId,
      editionId: editionId,
      chapterId: stored.first.id,
      fraction: 0.35,
      anchor: 'page:1',
    );
    expect(progress.fraction, 0.35);
    expect(progress.deviceId, 'test-device');

    final resume = await journey.loadResumeTarget(workId: workId, editionId: editionId);
    expect(resume!.canResume, isTrue);
    expect(resume.chapter!.id, stored.first.id);
    expect(resume.progress.anchor, 'page:1');

    final next = await journey.adjacentChapter(
      editionId: editionId,
      currentChapterId: stored.first.id,
      direction: 1,
    );
    expect(next!.chapterNumber, 2);

    final library = await journey.loadLibrary();
    expect(library, hasLength(1));
    expect(library.single.catalogEntry!.work.id, workId);
    expect(library.single.progress!.chapterId, stored.first.id);
    expect(library.single.record.lastOpenedAt, isNotNull);

    await journey.removeFromLibrary(workId: workId, editionId: editionId);
    expect(await journey.loadLibrary(), isEmpty);
    // Library membership and resumable progress are intentionally independent.
    expect(await journey.loadResumeTarget(workId: workId, editionId: editionId), isNotNull);
  });

  test('a failed identity match is queued instead of silently merged', () async {
    final known = await journey.openSeries((await journey.search('Blue Star')).candidates.single);
    expect(known.catalogResult.status, CatalogUpsertStatus.created);

    final uncertain = WorkCandidate(
      providerId: 'other-source',
      externalId: 'series-other',
      title: 'Blue Star',
      providerUrl: Uri.parse('https://other.example.org/title/series-other'),
      format: WorkFormat.unknown,
    );
    final result = await journey.saveListing(uncertain);
    expect(result.status, CatalogUpsertStatus.reviewRequired);
    expect(await database.loadPendingIdentityReviews(), hasLength(1));

    final resolved = await journey.resolveIdentityReview(
      uncertain.listingKey,
      createAsDistinctWork: true,
    );
    expect(resolved.status, CatalogUpsertStatus.created);
    expect(resolved.entry!.work.lockedDistinctIdentity, isTrue);
    expect(await database.loadPendingIdentityReviews(), isEmpty);
    expect((await database.loadCatalog()).length, 2);
  });

  test('disabled providers cannot be used to load details or chapters', () async {
    final candidate = (await journey.search('Blue Star')).candidates.single;
    final registry = journey.providers;
    registry.setEnabled(provider.descriptor.id, false);

    await expectLater(
      journey.openSeries(candidate),
      throwsStateError,
    );
  });
}
