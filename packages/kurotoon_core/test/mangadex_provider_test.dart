import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

class FakeTransport implements JsonGetTransport {
  FakeTransport(this.response);

  final JsonHttpResponse response;
  Uri? requested;

  @override
  Future<JsonHttpResponse> get(
    Uri uri, {
    required CancellationToken cancellationToken,
  }) async {
    requested = uri;
    cancellationToken.throwIfCancelled();
    return response;
  }
}

void main() {
  test('parses MangaDex search records without losing source listing identity', () async {
    final transport = FakeTransport(JsonHttpResponse(
      statusCode: 200,
      headers: const {},
      body: {
        'data': [
          {
            'id': 'series-id',
            'attributes': {
              'title': {'en': 'A Test Series', 'ja': 'テストシリーズ'},
              'altTitles': [
                {'en': 'The Test Series'},
              ],
              'year': 2024,
              'originalLanguage': 'ko',
              'description': {'en': 'A synopsis'},
              'tags': [
                {
                  'attributes': {
                    'name': {'en': 'Fantasy'},
                  },
                },
              ],
            },
            'relationships': [
              {'id': 'cover-id', 'type': 'cover_art'},
              {'id': 'author-id', 'type': 'author'},
            ],
          },
        ],
        'included': [
          {
            'id': 'cover-id',
            'type': 'cover_art',
            'attributes': {'fileName': 'cover-file.jpg'},
          },
          {
            'id': 'author-id',
            'type': 'author',
            'attributes': {'name': 'A. Writer'},
          },
        ],
      },
    ));
    final provider = MangaDexProvider(transport: transport);
    final response = await provider.search('test', cancellationToken: CancellationToken());

    expect(response.status, ProviderResultStatus.success);
    expect(response.data, hasLength(1));
    final item = response.data!.single;
    expect(item.providerId, 'mangadex');
    expect(item.externalId, 'series-id');
    expect(item.title, 'A Test Series');
    expect(item.alternateTitles, contains('The Test Series'));
    expect(item.creatorNames, contains('A. Writer'));
    expect(item.format, WorkFormat.manhwa);
    expect(item.coverUrl.toString(),
        'https://uploads.mangadex.org/covers/series-id/cover-file.jpg.256.jpg');
    expect(item.providerUrl.toString(), 'https://mangadex.org/title/series-id');
    expect(transport.requested!.queryParameters['title'], 'test');
    expect(transport.requested!.queryParametersAll['includes[]'], contains('author'));
    expect(transport.requested!.queryParametersAll['contentRating[]'], contains('safe'));
  });

  test('returns an explicit retry hint on rate limiting', () async {
    final transport = FakeTransport(const JsonHttpResponse(
      statusCode: 429,
      headers: {'retry-after': ['30']},
      body: {},
    ));
    final response = await MangaDexProvider(transport: transport).search(
      'series',
      cancellationToken: CancellationToken(),
    );
    expect(response.status, ProviderResultStatus.rateLimited);
    expect(response.retryAfter, const Duration(seconds: 30));
  });

  test('pre-cancelled query performs no request and returns cancelled', () async {
    final transport = FakeTransport(const JsonHttpResponse(
      statusCode: 200,
      headers: {},
      body: {'data': []},
    ));
    final token = CancellationToken()..cancel('User navigated away');
    final response = await MangaDexProvider(transport: transport).search('series', cancellationToken: token);
    expect(response.status, ProviderResultStatus.cancelled);
    expect(transport.requested, isNull);
  });

  test('rejects a malformed API response explicitly', () async {
    final transport = FakeTransport(const JsonHttpResponse(
      statusCode: 200,
      headers: {},
      body: {},
    ));
    final response = await MangaDexProvider(transport: transport).search(
      'series',
      cancellationToken: CancellationToken(),
    );
    expect(response.status, ProviderResultStatus.failed);
    expect(response.data, isNull);
  });
}
