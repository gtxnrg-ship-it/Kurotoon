import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

DeclarativeExtensionManifest makeManifest({
  Uri? base,
  Set<String>? hosts,
  String endpointPath = '/search',
  String license = 'MIT',
}) => DeclarativeExtensionManifest(
      id: 'org.example.source',
      name: 'Example Source',
      version: '1.0.0',
      minimumAppApi: 1,
      homepage: Uri.parse('https://source.example.org'),
      baseUri: base ?? Uri.parse('https://api.source.example.org/v1'),
      licenseId: license,
      developer: 'Example Maintainers',
      allowedHosts: hosts ?? {'api.source.example.org', 'images.source.example.org'},
      endpoints: [
        JsonEndpointSpec(
          id: 'search',
          capability: ExtensionCapability.search,
          path: endpointPath,
          query: const {'q': '{query}', 'page': '{page}', 'limit': '{limit}'},
          resultPath: JsonPath(const ['data', 'items']),
          fields: {
            'id': JsonPath(['id']),
            'title': JsonPath(['title']),
            'url': JsonPath(['url']),
          },
        ),
      ],
    );

void main() {
  const policy = ExtensionManifestPolicy();

  test('accepts an exact-host declarative source and constructs encoded queries', () {
    final manifest = makeManifest();
    final report = policy.validate(manifest);
    expect(report.accepted, isTrue, reason: report.issues.join('; '));
    final uri = manifest.endpoints.single.buildUri(
      manifest.baseUri,
      queryText: 'a title & more',
      page: 2,
      limit: 30,
    );
    expect(uri.host, 'api.source.example.org');
    expect(uri.path, '/v1/search');
    expect(uri.queryParameters['q'], 'a title & more');
    expect(uri.queryParameters['page'], '2');
    expect(uri.queryParameters['limit'], '30');
  });

  test('rejects local hosts, HTTP, wildcard host allowances, and unapproved licenses', () {
    expect(policy.validate(makeManifest(base: Uri.parse('http://api.source.example.org/v1'))).accepted, isFalse);
    expect(policy.validate(makeManifest(base: Uri.parse('https://127.0.0.1/v1'))).accepted, isFalse);
    expect(policy.validate(makeManifest(hosts: {'api.source.example.org', '*.source.example.org'})).accepted, isFalse);
    expect(policy.validate(makeManifest(license: 'UNKNOWN')).accepted, isFalse);
  });

  test('rejects URL authorities, malformed encoding, and path traversal', () {
    expect(policy.validate(makeManifest(endpointPath: '//evil.example.org/search')).accepted, isFalse);
    expect(policy.validate(makeManifest(endpointPath: '/../secret')).accepted, isFalse);
    expect(policy.validate(makeManifest(endpointPath: 'https://evil.example.org/search')).accepted, isFalse);
    expect(policy.validate(makeManifest(endpointPath: '/%ZZ')).accepted, isFalse);
  });

  test('extracts only declared record objects and maps fields', () {
    const extractor = DeclarativeJsonExtractor();
    final endpoint = makeManifest().endpoints.single;
    final records = extractor.records(endpoint, {
      'data': {
        'items': [
          {'id': '1', 'title': 'First', 'url': 'https://source.example.org/1'},
          'malformed',
          {'id': '2', 'title': 'Second', 'url': 'https://source.example.org/2'},
        ],
      },
    });
    expect(records, hasLength(2));
    expect(extractor.fields(endpoint, records.first)['title'], 'First');
    expect(endpoint.validate(), isEmpty);
  });

  test('encodes path placeholders as a single path segment', () {
    final endpoint = JsonEndpointSpec(
      id: 'detail',
      capability: ExtensionCapability.seriesDetails,
      path: '/series/{seriesId}',
      query: const {},
      resultPath: JsonPath(const ['data']),
      fields: {
        'id': JsonPath(['id']),
        'title': JsonPath(['title']),
        'url': JsonPath(['url']),
      },
    );
    final uri = endpoint.buildUri(Uri.parse('https://api.source.example.org'), seriesId: 'a/b?x=1');
    expect(uri.toString(), contains('a%2Fb%3Fx%3D1'));
    expect(uri.host, 'api.source.example.org');
  });
}
