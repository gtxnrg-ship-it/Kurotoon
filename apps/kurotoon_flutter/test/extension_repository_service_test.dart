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
}
