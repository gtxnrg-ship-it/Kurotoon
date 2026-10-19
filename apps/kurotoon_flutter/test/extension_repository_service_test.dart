import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_flutter/services/extension_repository_service.dart';
import 'package:path/path.dart' as p;


List<int> _mihonVarint(int value) {
  final bytes = <int>[];
  var remaining = value;
  while (remaining >= 0x80) {
    bytes.add((remaining & 0x7f) | 0x80);
    remaining >>= 7;
  }
  bytes.add(remaining);
  return bytes;
}

List<int> _mihonBytes(int number, List<int> value) => [
      ..._mihonVarint((number << 3) | 2),
      ..._mihonVarint(value.length),
      ...value,
    ];

List<int> _mihonString(int number, String value) => _mihonBytes(number, utf8.encode(value));
List<int> _mihonInt(int number, int value) => [..._mihonVarint(number << 3), ..._mihonVarint(value)];

List<int> _mihonExtension(String name, String package, int sourceId) {
  final source = <int>[
    ..._mihonInt(1, sourceId),
    ..._mihonString(2, '$name Source'),
    ..._mihonString(3, 'en'),
  ];
  return [
    ..._mihonString(1, name),
    ..._mihonString(2, package),
    ..._mihonInt(5, 1),
    ..._mihonString(6, '1.0.0'),
    ..._mihonBytes(8, source),
  ];
}

List<int> _mihonRoot({bool external = false, List<int> extensions = const []}) => [
      ..._mihonString(1, 'Example Repository'),
      ..._mihonString(3, 'test-signing-key'),
      if (external)
        ..._mihonString(102, 'extensions.pb')
      else
        ..._mihonBytes(101, [for (final extension in extensions) ..._mihonBytes(1, extension)]),
    ];

void main() {
  group('ExtensionInstallPathPolicy', () {
    const extensionId = 'org.example.source';
    final extensionsRoot = p.join(p.separator, 'app', 'support', 'extensions');

    test('allows only the expected installed manifest layout', () {
      final manifest = p.join(
        extensionsRoot,
        extensionId,
        '1.2.3',
        'a1b2c3d4e5f6',
        'manifest.json',
      );

      expect(
        ExtensionInstallPathPolicy.isSafeManifestPath(
          extensionsRoot: extensionsRoot,
          extensionId: extensionId,
          manifestPath: manifest,
        ),
        isTrue,
      );
    });

    test('rejects arbitrary files outside the extension root', () {
      expect(
        ExtensionInstallPathPolicy.isSafeManifestPath(
          extensionsRoot: extensionsRoot,
          extensionId: extensionId,
          manifestPath: p.join(p.separator, 'app', 'support', 'settings.json'),
        ),
        isFalse,
      );
    });

    test('rejects traversal and a mismatched extension directory', () {
      for (final manifest in [
        p.join(extensionsRoot, '..', 'settings.json'),
        p.join(extensionsRoot, 'org.example.other', '1.2.3', 'a1b2c3d4e5f6', 'manifest.json'),
        p.join(extensionsRoot, extensionId, '1.2.3', 'not-a-digest', 'manifest.json'),
        p.join(extensionsRoot, extensionId, '1.2.3', 'a1b2c3d4e5f6', 'payload.bin'),
      ]) {
        expect(
          ExtensionInstallPathPolicy.isSafeManifestPath(
            extensionsRoot: extensionsRoot,
            extensionId: extensionId,
            manifestPath: manifest,
          ),
          isFalse,
          reason: 'Must reject unsafe path: $manifest',
        );
      }
    });

    test('rejects invalid extension IDs before path resolution', () {
      expect(
        ExtensionInstallPathPolicy.isSafeManifestPath(
          extensionsRoot: extensionsRoot,
          extensionId: '../outside',
          manifestPath: p.join(extensionsRoot, '../outside', 'manifest.json'),
        ),
        isFalse,
      );
    });
  });

  group('resolved repository address policy', () {
    bool blocked(String value) {
      final address = InternetAddress.tryParse(value);
      expect(address, isNotNull, reason: 'Test fixture must parse as an IP literal: $value');
      return ExtensionRepositoryService.isNonPublicAddress(address!);
    }

    test('blocks private, reserved and mapped IPv4 addresses', () {
      for (final address in [
        '0.0.0.0',
        '10.1.2.3',
        '127.0.0.1',
        '100.64.0.1',
        '169.254.0.1',
        '172.16.0.1',
        '192.168.1.1',
        '192.0.2.1',
        '198.18.0.1',
        '203.0.113.1',
        '224.0.0.1',
      ]) {
        expect(blocked(address), isTrue, reason: address);
      }
    });

    test('blocks private, mapped and special-purpose IPv6 addresses', () {
      for (final address in [
        '::',
        '::1',
        '::ffff:127.0.0.1',
        'fc00::1',
        'fd00::1',
        'fe80::1',
        'ff02::1',
        '2001:db8::1',
        '2001:0::1',
        '2002:7f00:1::1',
        '2001:10::1',
        '2001:20::1',
      ]) {
        expect(blocked(address), isTrue, reason: address);
      }
    });

    test('allows a public global-unicast IPv6 address', () {
      expect(blocked('2606:4700:4700::1111'), isFalse);
    });
  });
  group('Mihon repository metadata preview', () {
    final indexUri = Uri.parse('https://repo.example.org/index.pb');

    test('shows a bounded sample while preserving total extension and source counts', () {
      final bytes = _mihonRoot(extensions: [
        _mihonExtension('First Source', 'org.example.first', 1),
        _mihonExtension('Second Source', 'org.example.second', 2),
      ]);
      final preview = parseMihonRepositoryPreviewBytes(
        indexUri: indexUri,
        indexBytes: bytes,
        previewLimit: 1,
      );
      expect(preview.index.name, 'Example Repository');
      expect(preview.extensions, hasLength(1));
      expect(preview.extensionCount, 2);
      expect(preview.sourceCount, 2);
      expect(preview.hasMorePreviewEntries, isTrue);
      expect(preview.indexDigest, hasLength(64));
      expect(
        parseMihonRepositoryPreviewBytes(indexUri: indexUri, indexBytes: bytes, previewLimit: 1).indexDigest,
        preview.indexDigest,
      );
    });

    test('requires the external extension-list payload when the index references one', () {
      final bytes = _mihonRoot(external: true);
      expect(
        () => parseMihonRepositoryPreviewBytes(indexUri: indexUri, indexBytes: bytes),
        throwsFormatException,
      );
      final list = _mihonBytes(1, _mihonExtension('External Source', 'org.example.external', 7));
      final preview = parseMihonRepositoryPreviewBytes(
        indexUri: indexUri,
        indexBytes: bytes,
        extensionListBytes: list,
      );
      expect(preview.extensionCount, 1);
      expect(preview.extensions.single.packageName, 'org.example.external');
    });

    test('rejects an invalid preview limit and unexpected external payload', () {
      final embedded = _mihonRoot(extensions: [_mihonExtension('First Source', 'org.example.first', 1)]);
      expect(
        () => parseMihonRepositoryPreviewBytes(indexUri: indexUri, indexBytes: embedded, previewLimit: 101),
        throwsArgumentError,
      );
      expect(
        () => parseMihonRepositoryPreviewBytes(
          indexUri: indexUri,
          indexBytes: embedded,
          extensionListBytes: const [1],
        ),
        throwsFormatException,
      );
    });
  });

}