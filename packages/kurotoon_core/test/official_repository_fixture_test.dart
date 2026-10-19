import 'dart:convert';
import 'dart:io';

import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

void main() {
  test('official starter repository index and manifest stay verifiable', () async {
    const indexUri = 'https://raw.githubusercontent.com/gtxnrg-ship-it/Kurotoon/main/catalog/official/index.json';
    final indexBody = await File('../../catalog/official/index.json').readAsString();
    final index = const RepositoryIndexValidator().parse(
      body: indexBody,
      indexUri: Uri.parse(indexUri),
    );

    expect(index.id, 'org.kurotoon.official');
    expect(index.extensions, hasLength(1));
    final entry = index.extensions.single;
    expect(entry.id, 'org.kurotoon.jikan-metadata');
    expect(entry.capabilities, {ExtensionCapability.search});

    final manifestBytes = await File('../../catalog/official/extensions/jikan-metadata.json').readAsBytes();
    const ExtensionPackageVerifier().verify(bytes: manifestBytes, entry: entry);
    final decoded = jsonDecode(utf8.decode(manifestBytes, allowMalformed: false));
    expect(decoded, isA<Map>());
    final manifest = parseDeclarativeExtensionManifest(Map<String, Object?>.from(decoded as Map));

    expect(manifest.id, entry.id);
    expect(manifest.version, entry.version);
    expect(manifest.capabilities, {ExtensionCapability.search});
    expect(manifest.baseUri.host, 'api.jikan.moe');
    expect(manifest.endpoints.single.buildUri(
      manifest.baseUri,
      queryText: 'one piece',
      limit: 25,
    ).queryParameters, {'q': 'one piece', 'limit': '25'});
  });
}
