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

  group('Mihon repository preview payloads', () {
    final extension = <int>[
      ..._mihonString(1, 'Example Source'),
      ..._mihonString(2, 'eu.example.source'),
      ..._mihonString(6, '1.0.0'),
    ];
    final extensionList = <int>[..._mihonBytes(1, extension)];

    test('parses embedded lists and computes a stable digest', () {
      final indexBytes = <int>[
        ..._mihonString(1, 'Example Repository'),
        ..._mihonString(3, 'test-key'),
        ..._mihonBytes(101, extensionList),
      ];
      final preview = parseMihonRepositoryPreviewBytes(
        indexUri: Uri.parse('https://repo.example.org/index.pb'),
        indexBytes: indexBytes,
      );
      expect(preview.index.name, 'Example Repository');
      expect(preview.extensionCount, 1);
      expect(preview.extensions.single.packageName, 'eu.example.source');
      expect(preview.indexDigest, hasLength(64));
    });

    test('keeps large external-list previews bounded while counting all entries', () {
      final secondExtension = <int>[
        ..._mihonString(1, 'Second Source'),
        ..._mihonString(2, 'eu.example.second'),
        ..._mihonString(6, '2.0.0'),
      ];
      final listBytes = <int>[
        ..._mihonBytes(1, extension),
        ..._mihonBytes(1, secondExtension),
      ];
      final indexBytes = <int>[
        ..._mihonString(1, 'Example Repository'),
        ..._mihonString(3, 'test-key'),
        ..._mihonString(102, 'list.pb'),
      ];
      final preview = parseMihonRepositoryPreviewBytes(
        indexUri: Uri.parse('https://repo.example.org/index.pb'),
        indexBytes: indexBytes,
        extensionListBytes: listBytes,
        previewLimit: 1,
      );
      expect(preview.extensionCount, 2);
      expect(preview.extensions, hasLength(1));
      expect(preview.hasMorePreviewEntries, isTrue);
    });

    test('requires and incorporates the external extension-list payload', () {
      final indexBytes = <int>[
        ..._mihonString(1, 'Example Repository'),
        ..._mihonString(3, 'test-key'),
        ..._mihonString(102, 'list.pb'),
      ];
      final indexUri = Uri.parse('https://repo.example.org/index.pb');
      expect(
        () => parseMihonRepositoryPreviewBytes(indexUri: indexUri, indexBytes: indexBytes),
        throwsFormatException,
      );
      final preview = parseMihonRepositoryPreviewBytes(
        indexUri: indexUri,
        indexBytes: indexBytes,
        extensionListBytes: extensionList,
      );
      expect(preview.index.extensionListUrl, Uri.parse('https://repo.example.org/list.pb'));
      expect(preview.extensions, hasLength(1));
    });
  });

}