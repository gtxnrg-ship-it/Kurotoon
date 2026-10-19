import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

class ApiTransport implements JsonGetTransport {
  ApiTransport(this.response);
  final JsonHttpResponse response;
  Uri? lastUri;

  @override
  Future<JsonHttpResponse> get(Uri uri, {required CancellationToken cancellationToken}) async {
    lastUri = uri;
    cancellationToken.throwIfCancelled();
    return response;
  }
}

void main() {
  const seriesId = '11111111-1111-4111-8111-111111111111';
  const chapterId = '22222222-2222-4222-8222-222222222222';

  test('multimedia provider exposes series metadata and truthful capabilities', () async {
    final transport = ApiTransport(const JsonHttpResponse(
      statusCode: 200,
      headers: {},
      body: {
        'data': {
          'id': seriesId,
          'attributes': {
            'title': {'en': 'A Series'},
            'altTitles': [
              {'ja': 'シリーズ'},
            ],
            'year': 2022,
            'originalLanguage': 'ja',
            'description': {'en': 'A synopsis'},
          },
          'relationships': [
            {'type': 'cover_art', 'id': 'cover-id'},
          ],
        },
        'included': [
          {
            'id': 'cover-id',
            'type': 'cover_art',
            'attributes': {'fileName': 'cover.jpg'},
          },
        ],
      },
    ));
    final provider = MangaDexMultimediaProvider(transport: transport);
    final response = await provider.getSeries(seriesId, cancellationToken: CancellationToken());

    expect(provider.descriptor.supports(ProviderCapability.search), isTrue);
    expect(provider.descriptor.supports(ProviderCapability.pages), isTrue);
    expect(response.status, ProviderResultStatus.success);
    expect(response.data!.title, 'A Series');
    expect(response.data!.coverUrl!.host, 'uploads.mangadex.org');
    expect(transport.lastUri!.path, '/manga/$seriesId');
  });

  test('maps chapter feed records into logical chapter units with provenance', () async {
    final transport = ApiTransport(const JsonHttpResponse(
      statusCode: 200,
      headers: {},
      body: {
        'total': 1,
        'data': [
          {
            'id': chapterId,
            'attributes': {
              'chapter': '1',
              'volume': '1',
              'title': 'Opening',
              'translatedLanguage': 'en',
              'readableAt': '2026-01-01T00:00:00+00:00',
            },
            'relationships': [
              {'type': 'scanlation_group', 'id': 'group-id'},
            ],
          },
        ],
      },
    ));
    final provider = MangaDexMultimediaProvider(transport: transport);
    final response = await provider.getChapters(
      seriesId,
      cancellationToken: CancellationToken(),
      translatedLanguages: const ['en', 'ja'],
    );

    expect(response.status, ProviderResultStatus.success);
    expect(response.data, hasLength(1));
    expect(response.data!.single.chapterNumber, 1);
    expect(response.data!.single.listings.single.providerId, 'mangadex');
    expect(response.data!.single.listings.single.releaseGroup, 'group-id');
    expect(transport.lastUri!.queryParametersAll['translatedLanguage[]'], ['en', 'ja']);
  });

  test('constructs temporary reader page URLs and rejects an untrusted host', () async {
    final transport = ApiTransport(const JsonHttpResponse(
      statusCode: 200,
      headers: {},
      body: {
        'baseUrl': 'https://uploads.mangadex.org',
        'chapter': {
          'hash': 'page-hash',
          'data': ['01.jpg', '02.jpg'],
          'dataSaver': ['01.jpg'],
        },
      },
    ));
    final provider = MangaDexMultimediaProvider(transport: transport);
    final response = await provider.getPages(
      chapterId,
      cancellationToken: CancellationToken(),
      dataSaver: true,
    );
    expect(response.status, ProviderResultStatus.success);
    expect(response.data!.urls(dataSaver: true), hasLength(1));
    expect(response.data!.urls(dataSaver: true).single.toString(),
        'https://uploads.mangadex.org/data-saver/page-hash/01.jpg');

    final untrusted = MangaDexMultimediaProvider(
      transport: ApiTransport(const JsonHttpResponse(
        statusCode: 200,
        headers: {},
        body: {
          'baseUrl': 'https://evil.example.org',
          'chapter': {'hash': 'hash', 'data': ['01.jpg'], 'dataSaver': ['01.jpg']},
        },
      )),
    );
    expect(
      (await untrusted.getPages(chapterId, cancellationToken: CancellationToken())).status,
      ProviderResultStatus.failed,
    );
  });

  test('rejects malformed IDs before making network requests', () async {
    final transport = ApiTransport(const JsonHttpResponse(statusCode: 200, headers: {}, body: {}));
    final provider = MangaDexMultimediaProvider(transport: transport);
    final response = await provider.getPages('not-a-uuid', cancellationToken: CancellationToken());
    expect(response.status, ProviderResultStatus.failed);
    expect(transport.lastUri, isNull);
  });
}
