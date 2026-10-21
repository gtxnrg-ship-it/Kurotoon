import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_flutter/services/extension_repository_service.dart';
import 'package:kurotoon_flutter/storage/kurotoon_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
      await Link(p.join(root, extensionId)).create(outside);

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



  group('Extension operation crash recovery', () {
    late Directory temp;
    late Directory support;
    late KurotoonDatabase database;
    late ExtensionRepositoryService service;

    const extensionId = 'org.example.source';
    const repositoryId = 'test.repository';

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('kurotoon-extension-recovery-');
      support = Directory(p.join(temp.path, 'support'));
      await support.create(recursive: true);
      database = await KurotoonDatabase.open(
        databasePath: p.join(temp.path, 'test.db'),
        factory: databaseFactoryFfi,
      );
      service = ExtensionRepositoryService(
        database: database,
        supportDirectoryProvider: () async => support,
      );
    });

    tearDown(() async {
      service.dispose();
      await database.close();
      await temp.delete(recursive: true);
    });

    String manifestPath(String digest12) => p.join(
          support.path,
          'extensions',
          extensionId,
          '1.0.0',
          digest12,
          'manifest.json',
        );

    Future<void> seedRepository() async {
      await database.rawDatabase.insert('extension_repositories', {
        'id': repositoryId,
        'name': 'Test repository',
        'index_url': 'https://example.org/index.json',
        'description': null,
        'website_url': null,
        'icon_url': null,
        'trust': 'community',
        'added_at': 1,
        'last_checked_at': 1,
        'last_index_digest': null,
      });
    }

    Future<void> seedInstalled(String path) async {
      await seedRepository();
      await database.rawDatabase.insert('installed_extensions', {
        'extension_id': extensionId,
        'repository_id': repositoryId,
        'name': 'Test source',
        'version': '1.0.0',
        'manifest_url': 'https://example.org/manifest.json',
        'sha256': sha256.convert(utf8.encode('{}')).toString(),
        'size_bytes': 2,
        'enabled': 1,
        'install_path': path,
        'installed_at': 1,
      });
    }

    test('rolls back a manifest file left before install metadata commits', () async {
      const digest12 = '0123456789ab';
      final targetPath = manifestPath(digest12);
      final temporaryPath = p.join(p.dirname(targetPath), '.manifest-123.tmp');
      await Directory(p.dirname(targetPath)).create(recursive: true);
      await File(targetPath).writeAsString('uncommitted manifest');
      await File(temporaryPath).writeAsString('partial manifest');
      await database.beginExtensionOperationJournal(
        id: 'install-crash-before-commit',
        operation: 'install',
        extensionId: extensionId,
        payload: {
          'targetPath': targetPath,
          'temporaryPath': temporaryPath,
          'targetExisted': false,
          'expectedSha256': sha256.convert(utf8.encode('{}')).toString(),
          'previousPath': null,
        },
      );

      final report = await service.recoverInterruptedOperations();

      expect(await File(targetPath).exists(), isFalse);
      expect(await File(temporaryPath).exists(), isFalse);
      expect(await database.loadInstalledExtensions(), isEmpty);
      expect(await database.loadExtensionOperationJournals(), isEmpty);
      expect(report.operationsRecovered, 1);
      expect(report.orphanManifestsRemoved, 1);
      expect(report.complete, isTrue);
    });

    test('finishes an install committed to SQLite before old-file cleanup', () async {
      const digest12 = 'abcdef012345';
      final targetPath = manifestPath(digest12);
      final temporaryPath = p.join(p.dirname(targetPath), '.manifest-321.tmp');
      final targetBytes = utf8.encode('{}');
      await Directory(p.dirname(targetPath)).create(recursive: true);
      await File(targetPath).writeAsBytes(targetBytes);
      await File(temporaryPath).writeAsString('stale temp');
      final previousPath = manifestPath('fedcba987654');
      await Directory(p.dirname(previousPath)).create(recursive: true);
      await File(previousPath).writeAsString('{}');
      await seedInstalled(targetPath);
      await database.beginExtensionOperationJournal(
        id: 'install-crash-after-commit',
        operation: 'install',
        extensionId: extensionId,
        payload: {
          'targetPath': targetPath,
          'temporaryPath': temporaryPath,
          'targetExisted': false,
          'expectedSha256': sha256.convert(targetBytes).toString(),
          'previousPath': previousPath,
        },
      );

      final report = await service.recoverInterruptedOperations();

      expect(await File(targetPath).readAsString(), '{}');
      expect(await File(temporaryPath).exists(), isFalse);
      expect(await File(previousPath).exists(), isFalse);
      expect((await database.loadInstalledExtensions()).single['install_path'], targetPath);
      expect(await database.loadExtensionOperationJournals(), isEmpty);
      expect(report.installRecordsCompleted, 1);
      expect(report.temporaryFilesRemoved, 1);
      expect(report.orphanManifestsRemoved, 1);
      expect(report.complete, isTrue);
    });

    test('cancels an uninstall journal if the installed row still exists', () async {
      const digest12 = '0123abcdef45';
      final targetPath = manifestPath(digest12);
      await Directory(p.dirname(targetPath)).create(recursive: true);
      await File(targetPath).writeAsString('{}');
      await seedInstalled(targetPath);
      await database.beginExtensionOperationJournal(
        id: 'uninstall-crash-before-delete',
        operation: 'uninstall',
        extensionId: extensionId,
        payload: {'manifestPath': targetPath},
      );

      final report = await service.recoverInterruptedOperations();

      expect(await File(targetPath).readAsString(), '{}');
      expect(await database.loadInstalledExtensions(), hasLength(1));
      expect(await database.loadExtensionOperationJournals(), isEmpty);
      expect(report.uninstallRecordsCompleted, 0);
      expect(report.complete, isTrue);
    });

    test('finishes an uninstall after the database row was removed', () async {
      const digest12 = '89abcdef0123';
      final targetPath = manifestPath(digest12);
      await Directory(p.dirname(targetPath)).create(recursive: true);
      await File(targetPath).writeAsString('{}');
      await seedInstalled(targetPath);
      await database.beginExtensionOperationJournal(
        id: 'uninstall-crash-after-delete',
        operation: 'uninstall',
        extensionId: extensionId,
        payload: {'manifestPath': targetPath},
      );
      await database.removeInstalledExtension(extensionId);

      final report = await service.recoverInterruptedOperations();

      expect(await File(targetPath).exists(), isFalse);
      expect(await database.loadInstalledExtensions(), isEmpty);
      expect(await database.loadExtensionOperationJournals(), isEmpty);
      expect(report.uninstallRecordsCompleted, 1);
      expect(report.orphanManifestsRemoved, 1);
      expect(report.complete, isTrue);
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