import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:kurotoon_flutter/services/reading_workflow_service.dart';
import 'package:kurotoon_flutter/storage/kurotoon_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeReaderProvider implements SourceProvider, SeriesProvider, ChapterFeedProvider, ReaderPagesProvider {
  _FakeReaderProvider({required this.providerId, this.editionIdOverride, this.languageOverride, this.hangChapterRequests = false})
      : _chapters = List<ChapterUnit>.generate(3, (index) {
          final id = 'chapter-${index + 1}';
          return ChapterUnit(
            id: id,
            editionId: editionIdOverride ?? '${providerId}:series-1:en',
            title: 'Chapter ${index + 1}',
            chapterNumber: index + 1,
            kind: ChapterKind.regular,
            listings: [
              ChapterListing(
                providerId: providerId,
                externalId: id,
                url: Uri.https('${providerId}.example.org', '/chapter/$id'),
                languageCode: languageOverride ?? 'en',
                publishedAt: DateTime.utc(2026, 1, index + 1),
              ),
            ],
          );
        });

  final String providerId;
  final String? editionIdOverride;
  final String? languageOverride;
  final bool hangChapterRequests;
  final String title = 'Blue Star';
  final List<ChapterUnit> _chapters;
  int pageRequests = 0;
  String? lastRequestedPageChapterId;

  @override
  late final ProviderDescriptor descriptor = ProviderDescriptor(
    id: providerId,
    name: providerId,
    homepage: Uri.https('${providerId}.example.org'),
    capabilities: {
      ProviderCapability.search,
      ProviderCapability.series,
      ProviderCapability.chapters,
      ProviderCapability.pages,
    },
    enabledByDefault: true,
  );

  WorkCandidate _candidate(String externalId) => WorkCandidate(
        providerId: providerId,
        externalId: externalId,
        title: title,
        alternateTitles: const ['The Blue Star'],
        creatorNames: providerId == 'reader-b' ? const [] : const ['A. Artist'],
        year: 2024,
        format: WorkFormat.manga,
        providerUrl: Uri.https('${providerId}.example.org', '/series/$externalId'),
        coverUrl: Uri.https('${providerId}.example.org', '/cover.jpg'),
        description: 'A test series.',
        tags: const ['Fantasy'],
      );

  @override
  Future<ProviderResponse<List<WorkCandidate>>> search(
    String query, {
    required CancellationToken cancellationToken,
  }) async =>
      ProviderResponse(status: ProviderResultStatus.success, data: [_candidate('series-1')]);

  @override
  Future<ProviderResponse<WorkCandidate>> getSeries(
    String seriesId, {
    required CancellationToken cancellationToken,
  }) async =>
      ProviderResponse(status: ProviderResultStatus.success, data: _candidate(seriesId));

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
    if (hangChapterRequests) {
      return Completer<ProviderResponse<List<ChapterUnit>>>().future;
    }
    final page = _chapters.skip(offset).take(limit).toList();
    return ProviderResponse(status: ProviderResultStatus.success, data: page);
  }

  @override
  Future<ProviderResponse<ReaderPageManifest>> getPages(
    String chapterId, {
    required CancellationToken cancellationToken,
    bool dataSaver = false,
  }) async {
    cancellationToken.throwIfCancelled();
    lastRequestedPageChapterId = chapterId;
    return ProviderResponse(
      status: ProviderResultStatus.success,
      data: ReaderPageManifest(
        chapterId: chapterId,
        baseUrl: Uri.https('cdn.example.org'),
        hash: 'abcdef0123456789abcdef0123456789',
        normalFilenames: const ['page-1.webp', 'page-2.webp'],
        dataSaverFilenames: const ['page-1.webp'],
      ),
    );
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory temp;
  late KurotoonDatabase database;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kurotoon-reading-workflow-');
    database = await KurotoonDatabase.open(
      databasePath: p.join(temp.path, 'test.db'),
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  WorkCandidate candidate(String providerId, {String title = 'Blue Star'}) => WorkCandidate(
        providerId: providerId,
        externalId: 'series-1',
        title: title,
        alternateTitles: const ['The Blue Star'],
        creatorNames: providerId == 'reader-b' ? const [] : const ['A. Artist'],
        year: 2024,
        format: WorkFormat.manga,
        providerUrl: Uri.https('$providerId.example.org', '/series/series-1'),
      );

  test('connects catalog selection, paginated chapters, reader manifests, library and resume progress', () async {
    final provider = _FakeReaderProvider(providerId: 'reader-a');
    final providers = ProviderRegistry()..register(provider);
    final workflow = ReadingWorkflowService(database: database, providers: providers, deviceId: 'test-device');

    final work = await workflow.prepareWork(candidate('reader-a'));
    expect(work.detailsStatus, ProviderResultStatus.success);
    expect(work.admissionResult.admission, CatalogAdmission.created);
    expect((await database.loadCatalog()).single.work.id, work.workId);

    final synced = await workflow.syncChapters(work, pageSize: 2, maxChapters: 10);
    expect(synced.status, ProviderResultStatus.success);
    expect(synced.reachedEnd, isTrue);
    expect(synced.nextOffset, 3);
    expect(synced.chapters, hasLength(3));
    expect(provider.pageRequests, 2);
    expect(await database.loadChapters(work.edition.id), hasLength(3));

    await workflow.addToLibrary(work, status: LibraryStatus.planned);
    final selected = synced.chapters[1];
    final pages = await workflow.loadReaderManifest(work, selected);
    expect(pages.status, ProviderResultStatus.success);
    expect(pages.data!.urls(), hasLength(2));
    expect(provider.lastRequestedPageChapterId, selected.listings.single.externalId);

    final saved = await workflow.saveProgress(work, selected, fraction: 0.42, anchor: 'page:2');
    expect(saved.chapterId, selected.id);
    expect(saved.fraction, 0.42);
    expect((await workflow.resumeProgress(work))!.chapterId, selected.id);

    final library = await database.loadLibrary();
    expect(library, hasLength(1));
    expect(library.single.status, LibraryStatus.reading);
    expect(library.single.lastOpenedAt, isNotNull);

    providers.dispose();
  });

  test('queues possible cross-source duplicate without silently merging identities', () async {
    final firstProvider = _FakeReaderProvider(providerId: 'reader-a');
    final secondProvider = _FakeReaderProvider(providerId: 'reader-b');
    final providers = ProviderRegistry()
      ..register(firstProvider)
      ..register(secondProvider);
    final workflow = ReadingWorkflowService(database: database, providers: providers, deviceId: 'test-device');

    final first = await workflow.prepareWork(candidate('reader-a'));
    final second = await workflow.prepareWork(candidate('reader-b'));

    expect(first.workId, isNot(second.workId));
    expect(second.admissionResult.admission, CatalogAdmission.reviewRequired);
    expect(await database.loadCatalog(), hasLength(2));
    expect(await database.loadPendingIdentityReviews(), hasLength(1));

    providers.dispose();
  });

  test('rejects chapter feeds that cross the prepared edition boundary', () async {
    final provider = _FakeReaderProvider(
      providerId: 'reader-a',
      editionIdOverride: 'another-work:en',
    );
    final providers = ProviderRegistry()..register(provider);
    final workflow = ReadingWorkflowService(database: database, providers: providers, deviceId: 'test-device');
    final work = await workflow.prepareWork(candidate('reader-a'));

    final result = await workflow.syncChapters(work, pageSize: 2, maxChapters: 10);
    expect(result.status, ProviderResultStatus.failed);
    expect(result.chapters, isEmpty);
    expect(await database.loadChapters(work.edition.id), isEmpty);

    providers.dispose();
  });

  test('rejects chapter feeds with a different translation language', () async {
    final provider = _FakeReaderProvider(
      providerId: 'reader-a',
      languageOverride: 'ja',
    );
    final providers = ProviderRegistry()..register(provider);
    final workflow = ReadingWorkflowService(database: database, providers: providers, deviceId: 'test-device');
    final work = await workflow.prepareWork(candidate('reader-a'));

    final result = await workflow.syncChapters(work, pageSize: 2, maxChapters: 10);
    expect(result.status, ProviderResultStatus.failed);
    expect(result.chapters, isEmpty);
    expect(await database.loadChapters(work.edition.id), isEmpty);

    providers.dispose();
  });

  test('bounds a provider that never completes chapter requests', () async {
    final provider = _FakeReaderProvider(
      providerId: 'reader-a',
      hangChapterRequests: true,
    );
    final providers = ProviderRegistry()..register(provider);
    final workflow = ReadingWorkflowService(
      database: database,
      providers: providers,
      deviceId: 'test-device',
      providerTimeout: const Duration(milliseconds: 20),
    );
    final work = await workflow.prepareWork(candidate('reader-a'));

    final result = await workflow.syncChapters(work, pageSize: 2, maxChapters: 10);
    expect(result.status, ProviderResultStatus.timedOut);
    expect(result.chapters, isEmpty);
    expect(result.reachedEnd, isFalse);

    providers.dispose();
  });

  test('rejects malformed language selections before making network requests', () async {
    final provider = _FakeReaderProvider(providerId: 'reader-a');
    final providers = ProviderRegistry()..register(provider);
    final workflow = ReadingWorkflowService(database: database, providers: providers, deviceId: 'test-device');

    await expectLater(
      workflow.prepareWork(candidate('reader-a'), languageCode: '../en'),
      throwsArgumentError,
    );
    expect(provider.pageRequests, 0);

    providers.dispose();
  });
  test('merges duplicate review while preserving the source edition, library and progress', () async {
    final providers = ProviderRegistry()
      ..register(_FakeReaderProvider(providerId: 'reader-a'))
      ..register(_FakeReaderProvider(providerId: 'reader-b'));
    final workflow = ReadingWorkflowService(database: database, providers: providers, deviceId: 'test-device');

    final original = await workflow.prepareWork(candidate('reader-a'));
    final duplicate = await workflow.prepareWork(candidate('reader-b'));
    expect(duplicate.admissionResult.admission, CatalogAdmission.reviewRequired);
    final synced = await workflow.syncChapters(duplicate, pageSize: 2, maxChapters: 10);
    expect(synced.chapters, hasLength(3));

    await workflow.addToLibrary(duplicate, status: LibraryStatus.reading);
    final saved = await workflow.saveProgress(
      duplicate,
      synced.chapters[1],
      fraction: 0.63,
      anchor: 'page:2',
    );

    final resolved = await workflow.resolveIdentityReview(
      'reader-b:series-1',
      targetWorkId: original.workId,
    );

    expect(resolved.admission, CatalogAdmission.linked);
    expect(resolved.entry.work.id, original.workId);
    final catalog = await database.loadCatalog();
    expect(catalog, hasLength(1));
    expect(catalog.single.providerIds, containsAll(['reader-a', 'reader-b']));
    expect(await database.loadPendingIdentityReviews(), isEmpty);
    expect((await database.loadEdition(duplicate.edition.id))!.workId, original.workId);

    final library = await database.loadLibrary();
    expect(library, hasLength(1));
    expect(library.single.workId, original.workId);
    expect(library.single.editionId, duplicate.edition.id);

    final progress = await database.loadProgress(original.workId, duplicate.edition.id);
    expect(progress, isNotNull);
    expect(progress!.chapterId, saved.chapterId);
    expect(progress.fraction, 0.63);
    expect(progress.anchor, 'page:2');

    providers.dispose();
  });

  test('confirming a separate identity removes its review and locks future auto-merges', () async {
    final providers = ProviderRegistry()
      ..register(_FakeReaderProvider(providerId: 'reader-a'))
      ..register(_FakeReaderProvider(providerId: 'reader-b'));
    final workflow = ReadingWorkflowService(database: database, providers: providers, deviceId: 'test-device');

    await workflow.prepareWork(candidate('reader-a'));
    final duplicate = await workflow.prepareWork(candidate('reader-b'));
    expect(duplicate.admissionResult.admission, CatalogAdmission.reviewRequired);

    final result = await workflow.resolveIdentityReview(
      'reader-b:series-1',
      createAsDistinctWork: true,
    );
    expect(result.admission, CatalogAdmission.distinctConfirmed);
    expect(result.entry.work.lockedDistinctIdentity, isTrue);
    expect(await database.loadPendingIdentityReviews(), isEmpty);
    final persisted = (await database.loadCatalog()).singleWhere(
      (entry) => entry.work.id == duplicate.workId,
    );
    expect(persisted.work.lockedDistinctIdentity, isTrue);
    expect((await database.loadEdition(duplicate.edition.id))!.workId, duplicate.workId);

    providers.dispose();
  });

}
