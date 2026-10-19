import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:kurotoon_flutter/services/reading_workflow_service.dart';
import 'package:kurotoon_flutter/storage/kurotoon_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeReaderProvider implements SourceProvider, SeriesProvider, ChapterFeedProvider, ReaderPagesProvider {
  _FakeReaderProvider({required this.providerId, this.title = 'Blue Star'})
      : _chapters = List<ChapterUnit>.generate(3, (index) {
          final id = 'chapter-${index + 1}';
          return ChapterUnit(
            id: id,
            editionId: '${providerId}:series-1:en',
            title: 'Chapter ${index + 1}',
            chapterNumber: index + 1,
            kind: ChapterKind.regular,
            listings: [
              ChapterListing(
                providerId: providerId,
                externalId: id,
                url: Uri.https('${providerId}.example.org', '/chapter/$id'),
                languageCode: 'en',
                publishedAt: DateTime.utc(2026, 1, index + 1),
              ),
            ],
          );
        });

  final String providerId;
  final String title;
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
}
