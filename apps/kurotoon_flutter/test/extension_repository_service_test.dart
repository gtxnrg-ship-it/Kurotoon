import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_flutter/services/extension_repository_service.dart';
import 'package:path/path.dart' as p;

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


    test('on-disk policy accepts a regular installed manifest', () async {
      final temp = await Directory.systemTemp.createTemp('kurotoon-extension-path-');
      addTearDown(() => temp.delete(recursive: true));
      final root = p.join(temp.path, 'extensions');
      final manifest = p.join(
        root,
        extensionId,
        '1.2.3',
        'a1b2c3d4e5f6',
        'manifest.json',
      );
      final file = File(manifest);
      await file.parent.create(recursive: true);
      await file.writeAsString('{}');

      expect(
        await ExtensionInstallPathPolicy.isSafeManifestPathOnDisk(
          extensionsRoot: root,
          extensionId: extensionId,
          manifestPath: manifest,
        ),
        isTrue,
      );
    });

    test('on-disk policy rejects a symlink inside the managed extension root', () async {
      final temp = await Directory.systemTemp.createTemp('kurotoon-extension-symlink-');
      addTearDown(() => temp.delete(recursive: true));
      final root = p.join(temp.path, 'extensions');
      final outside = p.join(temp.path, 'outside-source');
      await Directory(root).create(recursive: true);
      final outsideManifest = File(p.join(
        outside,
        '1.2.3',
        'a1b2c3d4e5f6',
        'manifest.json',
      ));
      await outsideManifest.parent.create(recursive: true);
      await outsideManifest.writeAsString('{}');
      await Link(p.join(root, extensionId)).create(target: outside);

      final apparentManifest = p.join(
        root,
        extensionId,
        '1.2.3',
        'a1b2c3d4e5f6',
        'manifest.json',
      );
      expect(
        ExtensionInstallPathPolicy.isSafeManifestPath(
          extensionsRoot: root,
          extensionId: extensionId,
          manifestPath: apparentManifest,
        ),
        isTrue,
        reason: 'The lexical path looks safe and so must not be the only check.',
      );
      expect(
        await ExtensionInstallPathPolicy.isSafeManifestPathOnDisk(
          extensionsRoot: root,
          extensionId: extensionId,
          manifestPath: apparentManifest,
        ),
        isFalse,
      );
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
}