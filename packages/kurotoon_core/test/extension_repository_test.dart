import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

const indexUri = 'https://raw.example.org/kurotoon/index.min.json';

Map<String, Object?> entryJson({
  String id = 'org.example.source',
  String manifestUrl = 'manifests/source.json',
  String digest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  int size = 10,
}) => {
      'id': id,
      'name': 'Example Source',
      'version': '1.0.0',
      'manifestUrl': manifestUrl,
      'sha256': digest,
      'sizeBytes': size,
      'minimumAppApi': 1,
      'capabilities': ['search', 'chapterFeed'],
      'languageCodes': ['en'],
      'contentRating': 'safe',
    };

Map<String, Object?> indexJson({List<Map<String, Object?>>? entries}) => {
      'schemaVersion': 1,
      'id': 'org.example.repository',
      'name': 'Example Repository',
      'generatedAt': '2026-10-19T00:00:00Z',
      'extensions': entries ?? [entryJson()],
    };

void main() {
  const validator = RepositoryIndexValidator();

  test('parses a repository index without downloading all extension packages', () {
    final index = validator.parse(
      body: jsonEncode(indexJson()),
      indexUri: Uri.parse(indexUri),
    );
    expect(index.name, 'Example Repository');
    expect(index.extensions, hasLength(1));
    expect(index.extensions.single.id, 'org.example.source');
    expect(index.extensions.single.manifestUri.path, '/kurotoon/manifests/source.json');
    expect(index.extensions.single.capabilities, contains(ExtensionCapability.search));
    expect(index.extensions.single.languageCodes, ['en']);
  });

  test('rejects duplicate extension ids and unsupported index versions', () {
    expect(
      () => validator.parse(
        body: jsonEncode(indexJson(entries: [entryJson(), entryJson()])),
        indexUri: Uri.parse(indexUri),
      ),
      throwsFormatException,
    );
    expect(
      () => validator.parse(
        body: jsonEncode({...indexJson(), 'schemaVersion': 77}),
        indexUri: Uri.parse(indexUri),
      ),
      throwsFormatException,
    );
  });

  test('rejects cross-origin package URLs, invalid hashes, and oversized entries', () {
    expect(
      () => validator.parse(
        body: jsonEncode(indexJson(entries: [entryJson(manifestUrl: 'https://evil.example/manifest.json')])),
        indexUri: Uri.parse(indexUri),
      ),
      throwsFormatException,
    );
    expect(
      () => validator.parse(
        body: jsonEncode(indexJson(entries: [entryJson(digest: 'not-a-hash')])),
        indexUri: Uri.parse(indexUri),
      ),
      throwsFormatException,
    );
    expect(
      () => validator.parse(
        body: jsonEncode(indexJson(entries: [entryJson(size: 3 * 1024 * 1024)])),
        indexUri: Uri.parse(indexUri),
      ),
      throwsFormatException,
    );
  });

  test('rejects private repository URLs and an index over the byte limit', () {
    expect(
      () => validator.parse(body: jsonEncode(indexJson()), indexUri: Uri.parse('https://127.0.0.1/index.json')),
      throwsFormatException,
    );
    expect(
      () => const RepositoryIndexValidator(maxIndexBytes: 8)
          .parse(body: jsonEncode(indexJson()), indexUri: Uri.parse(indexUri)),
      throwsFormatException,
    );
  });

  test('deep links carry only the repository URL and validate it on receipt', () {
    final source = Uri.parse(indexUri);
    final link = AddRepositoryLink.create(source);
    expect(link.scheme, 'kurotoon');
    expect(AddRepositoryLink.parse(link), source);
    expect(
      () => AddRepositoryLink.parse(Uri.parse('kurotoon://add-repo?url=http%3A%2F%2Flocalhost%2Findex.json')),
      throwsFormatException,
    );
  });

  test('verifies selected extension package by exact size and SHA-256', () {
    final bytes = utf8.encode('tiny declarative extension');
    final entry = ExtensionPackageEntry(
      id: 'org.example.source',
      name: 'Example Source',
      version: '1.0.0',
      manifestUri: Uri.parse('https://raw.example.org/kurotoon/source.json'),
      sha256: sha256.convert(bytes).toString(),
      sizeBytes: bytes.length,
      minimumAppApi: 1,
      capabilities: const {ExtensionCapability.search},
    );
    const ExtensionPackageVerifier().verify(bytes: bytes, entry: entry);
    expect(
      () => const ExtensionPackageVerifier().verify(
        bytes: utf8.encode('tampered'),
        entry: entry,
      ),
      throwsFormatException,
    );
  });
}
