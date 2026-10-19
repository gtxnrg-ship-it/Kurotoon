import 'dart:convert';

import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

List<int> _varint(int value) {
  final bytes = <int>[];
  var remaining = value;
  while (remaining >= 0x80) {
    bytes.add((remaining & 0x7f) | 0x80);
    remaining >>= 7;
  }
  bytes.add(remaining);
  return bytes;
}

List<int> _fieldVarint(int number, int value) => [
      ..._varint(number << 3),
      ..._varint(value),
    ];

List<int> _fieldBytes(int number, List<int> value) => [
      ..._varint((number << 3) | 2),
      ..._varint(value.length),
      ...value,
    ];

List<int> _fieldString(int number, String value) => _fieldBytes(number, utf8.encode(value));

void main() {
  final source = <int>[
    ..._fieldVarint(1, 123456),
    ..._fieldString(2, 'MangaDex'),
    ..._fieldString(3, 'en'),
    ..._fieldString(4, 'https://mangadex.org'),
    ..._fieldString(5, 'https://mangadex.org/mirror'),
    ..._fieldString(7, 'Community adapter required'),
  ];
  final resources = <int>[
    ..._fieldString(1, 'https://repo.example.org/source.apk'),
    ..._fieldString(2, 'https://repo.example.org/source.png'),
    ..._fieldString(501, 'https://repo.example.org/source.jar'),
  ];
  final extension = <int>[
    ..._fieldString(1, 'Example Source'),
    ..._fieldString(2, 'eu.example.source'),
    ..._fieldBytes(3, resources),
    ..._fieldVarint(5, 42),
    ..._fieldString(6, '1.2.3'),
    ..._fieldVarint(7, 1),
    ..._fieldBytes(8, source),
  ];
  final extensionList = <int>[..._fieldBytes(1, extension)];
  final indexBytes = <int>[
    ..._fieldString(1, 'Example Mihon Repository'),
    ..._fieldString(2, 'Community'),
    ..._fieldString(3, 'test-signing-key'),
    ..._fieldBytes(101, extensionList),
  ];

  test('parses embedded Mihon protobuf indexes and source metadata', () {
    final index = MihonRepositoryIndex.parse(
      indexBytes,
      indexUri: Uri.parse('https://repo.example.org/index.pb'),
    );
    expect(index.name, 'Example Mihon Repository');
    expect(index.badgeLabel, 'Community');
    expect(index.signingKey, 'test-signing-key');
    expect(index.hasExternalExtensionList, isFalse);
    expect(index.extensions, hasLength(1));
    expect(index.sourceCount, 1);

    final entry = index.extensions.single;
    expect(entry.name, 'Example Source');
    expect(entry.packageName, 'eu.example.source');
    expect(entry.versionCode, 42);
    expect(entry.versionName, '1.2.3');
    expect(entry.contentWarning, MihonContentWarning.safe);
    expect(entry.resources.apkUrl!.host, 'repo.example.org');
    expect(entry.resources.jarUrl!.path, '/source.jar');
    expect(entry.sources.single.id, 123456);
    expect(entry.sources.single.name, 'MangaDex');
    expect(entry.sources.single.language, 'en');
    expect(entry.sources.single.mirrorUrls.single.host, 'mangadex.org');
  });

  test('resolves an external extension-list URL against the repository index', () {
    final bytes = <int>[
      ..._fieldString(1, 'External List Repository'),
      ..._fieldString(3, 'test-signing-key'),
      ..._fieldString(102, 'lists/index.pb'),
    ];
    final index = MihonRepositoryIndex.parse(
      bytes,
      indexUri: Uri.parse('https://repo.example.org/index.pb'),
    );
    expect(index.hasExternalExtensionList, isTrue);
    expect(index.extensions, isEmpty);
    expect(index.extensionListUrl, Uri.parse('https://repo.example.org/lists/index.pb'));
    expect(
      MihonRepositoryIndex.parseExtensionList(extensionList).single.packageName,
      'eu.example.source',
    );
  });

  test('rejects malformed protobuf, oversized input, and missing repository metadata', () {
    expect(
      () => MihonRepositoryIndex.parse([0x0a, 0x05, 0x41], indexUri: Uri.parse('https://repo.example.org/index.pb')),
      throwsFormatException,
    );
    expect(
      () => MihonRepositoryIndex.parse(indexBytes, indexUri: Uri.parse('https://repo.example.org/index.pb'), maxBytes: 1),
      throwsFormatException,
    );
    expect(
      () => MihonRepositoryIndex.parse(_fieldString(1, 'Missing key'), indexUri: Uri.parse('https://repo.example.org/index.pb')),
      throwsFormatException,
    );
  });
}
