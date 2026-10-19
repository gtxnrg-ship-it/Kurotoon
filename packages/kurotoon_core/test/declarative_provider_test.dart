import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

class FakeFetcher implements DeclarativeJsonFetcher {
  FakeFetcher(this.payload, {this.error});

  final Object? payload;
  final DeclarativeFetchException? error;
  Uri? lastUri;

  @override
  Future<Object?> getJson(
    Uri uri, {
    required CancellationToken cancellationToken,
    required int maxResponseBytes,
  }) async {
    cancellationToken.throwIfCancelled();
    lastUri = uri;
    if (error != null) throw error!;
    return payload;
  }

  test('maps chapter feeds and reader page manifests through declared paths', () async {
    final manifest = parseDeclarativeExtensionManifest({
      'id': 'org.example.fullsource',
      'name': 'Full Example Source',
      'version': '1.0.0',
      'minimumAppApi': 1,
      'homepage': 'https://source.example.org',
      'baseUrl': 'https://api.source.example.org/v1',
      'license': 'MIT',
      'developer': 'Example Maintainers',
      'allowedHosts': ['api.source.example.org', 'source.example.org', 'images.example.org'],
      'endpoints': [
        {
          'id': 'chapters',
          'capability': 'chapterFeed',
          'path': '/series/{seriesId}/chapters',
          'query': {'page': '{page}', 'limit': '{limit}', 'language': '{language}'},
          'resultPath': ['data', 'items'],
          'fields': {
            'id': ['id'],
            'title': ['title'],
            'url': ['url'],
            'chapterNumber': ['number'],
            'kind': ['kind'],
            'miniGroupId': ['miniGroupId'],
            'miniIndex': ['miniIndex'],
            'miniCount': ['miniCount'],
            'languageCode': ['language'],
          },
        },
        {
          'id': 'pages',
          'capability': 'readerPages',
          'path': '/chapter/{chapterId}/pages',
          'query': {},
          'resultPath': ['data'],
          'fields': {
            'baseUrl': ['baseUrl'],
            'hash': ['hash'],
            'filenames': ['filenames'],
            'dataSaverFilenames': ['dataSaverFilenames'],
          },
        },
      ],
    });

    final chapterFetcher = FakeFetcher({
      'data': {
        'items': [
          {
            'id': 'mini-1',
            'title': 'Part 1',
            'url': 'https://source.example.org/chapter/mini-1',
            'number': 3,
            'kind': 'miniChapter',
            'miniGroupId': 'chapter-3',
            'miniIndex': 1,
            'miniCount': 6,
            'language': 'en',
          },
        ],
      },
    });
    final provider = DeclarativeJsonProvider(manifest: manifest, fetcher: chapterFetcher);
    final chapterResponse = await provider.getChapters(
      'series-1',
      cancellationToken: CancellationToken(),
    );
    expect(chapterResponse.status, ProviderResultStatus.success);
    expect(chapterResponse.data!.single.kind, ChapterKind.miniChapter);
    expect(chapterResponse.data!.single.miniCount, 6);
    expect(chapterResponse.data!.single.listings.single.languageCode, 'en');

    final pageFetcher = FakeFetcher({
      'data': {
        'baseUrl': 'https://images.example.org/pages',
        'hash': 'abc123',
        'filenames': ['001.webp', '002.webp'],
        'dataSaverFilenames': ['001-small.webp'],
      },
    });
    final pageProvider = DeclarativeJsonProvider(manifest: manifest, fetcher: pageFetcher);
    final pageResponse = await pageProvider.getPages(
      'chapter-1',
      cancellationToken: CancellationToken(),
      dataSaver: true,
    );
    expect(pageResponse.status, ProviderResultStatus.success);
    expect(pageResponse.data!.normalFilenames, ['001.webp', '002.webp']);
    expect(pageResponse.data!.urls(dataSaver: true).length, 1);
  });

}

DeclarativeExtensionManifest makeManifest() => parseDeclarativeExtensionManifest({
      'id': 'org.example.source',
      'name': 'Example Source',
      'version': '1.0.0',
      'minimumAppApi': 1,
      'homepage': 'https://source.example.org',
      'baseUrl': 'https://api.source.example.org/v1',
      'license': 'MIT',
      'developer': 'Example Maintainers',
      'allowedHosts': ['api.source.example.org', 'source.example.org', 'images.example.org'],
      'endpoints': [
        {
          'id': 'search',
          'capability': 'search',
          'path': '/search',
          'query': {'q': '{query}', 'page': '{page}', 'limit': '{limit}'},
          'resultPath': ['data', 'items'],
          'fields': {
            'id': ['id'],
            'title': ['title'],
            'url': ['url'],
            'coverUrl': ['cover'],
            'creatorNames': ['authors'],
            'year': ['year'],
            'format': ['format'],
          },
        },
      ],
    });

void main() {
  test('searches using only declared endpoints and normalizes mapped fields', () async {
    final fetcher = FakeFetcher({
      'data': {
        'items': [
          {
            'id': 'series-1',
            'title': 'Blue Star',
            'url': 'https://source.example.org/series/1',
            'cover': 'https://images.example.org/cover.webp',
            'authors': ['A. Artist'],
            'year': 2024,
            'format': 'webtoon',
          },
          {
            'id': 'unsafe',
            'title': 'Unsafe external result',
            'url': 'https://evil.example/series/2',
          },
        ],
      },
    });
    final provider = DeclarativeJsonProvider(manifest: makeManifest(), fetcher: fetcher);
    final response = await provider.search(
      'Blue Star & more',
      cancellationToken: CancellationToken(),
    );
    expect(fetcher.lastUri!.queryParameters['q'], 'Blue Star & more');
    expect(response.status, ProviderResultStatus.success);
    expect(response.data, hasLength(1));
    expect(response.data!.single.title, 'Blue Star');
    expect(response.data!.single.format, WorkFormat.webtoon);
    expect(response.data!.single.creatorNames, ['A. Artist']);
    expect(response.data!.single.coverUrl!.host, 'images.example.org');
  });

  test('maps rate limiting and cancellation to explicit provider states', () async {
    final rateLimited = DeclarativeJsonProvider(
      manifest: makeManifest(),
      fetcher: FakeFetcher(null, error: const DeclarativeFetchException(429, retryAfter: Duration(seconds: 20))),
    );
    final rateResponse = await rateLimited.search('title', cancellationToken: CancellationToken());
    expect(rateResponse.status, ProviderResultStatus.rateLimited);
    expect(rateResponse.retryAfter, const Duration(seconds: 20));

    final token = CancellationToken()..cancel('user stopped');
    final cancelled = await rateLimited.search('title', cancellationToken: token);
    expect(cancelled.status, ProviderResultStatus.cancelled);
  });

  test('does not fetch blank queries and reports unsupported search', () async {
    final fetcher = FakeFetcher({'data': {'items': []}});
    final provider = DeclarativeJsonProvider(manifest: makeManifest(), fetcher: fetcher);
    final empty = await provider.search('  ', cancellationToken: CancellationToken());
    expect(empty.data, isEmpty);
    expect(fetcher.lastUri, isNull);
  });
}
