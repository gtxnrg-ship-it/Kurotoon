import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:kurotoon_flutter/storage/kurotoon_database.dart';
import 'package:kurotoon_flutter/storage/voice_pack_storage_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory temp;
  late KurotoonDatabase database;
  late VoicePackStorageService service;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kurotoon-voice-pack-test-');
    database = await KurotoonDatabase.open(
      databasePath: p.join(temp.path, 'test.db'),
      factory: databaseFactoryFfi,
    );
    service = VoicePackStorageService(
      database: database,
      rootDirectory: Directory(p.join(temp.path, 'voice_packs')),
    );
  });

  tearDown(() async {
    service.dispose();
    await database.close();
    await temp.delete(recursive: true);
  });

  VoicePackManifest manifest() => VoicePackManifest(
        id: 'org.example.voice',
        displayName: 'Example Open Voice',
        version: '1.0.0',
        locale: 'en',
        licenseId: 'Apache-2.0',
        licenseUrl: Uri.parse('https://licenses.example.org/apache-2.0'),
        downloadUrl: Uri.parse('https://models.example.org/voice.bin'),
        sha256: 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        compressedBytes: 3,
      );

  test('requires explicit user opt-in before resolving or downloading a voice pack', () async {
    await expectLater(
      service.install(
        manifest(),
        downloadsEnabled: false,
        availableStorageBytes: 100,
      ),
      throwsA(isA<VoicePackInstallException>()),
    );
    expect(await database.loadVoicePackInstall('org.example.voice'), isNull);
  });

  test('reuses a verified local pack without network access', () async {
    final pack = manifest();
    final local = File(p.join(
      temp.path,
      'voice_packs',
      pack.id,
      pack.version,
      pack.sha256,
      'model.bin',
    ));
    await local.parent.create(recursive: true);
    await local.writeAsBytes([97, 98, 99], flush: true);

    final installedPath = await service.install(
      pack,
      downloadsEnabled: true,
      availableStorageBytes: 100,
    );

    expect(installedPath, local.path);
    expect(await database.loadVoicePackInstall(pack.id), isNotNull);
  });

  test('rejects invalid IDs without touching the network', () async {
    final invalid = VoicePackManifest(
      id: '../outside',
      displayName: 'Unsafe',
      version: '1',
      locale: 'en',
      licenseId: 'Apache-2.0',
      licenseUrl: Uri.parse('https://licenses.example.org/apache-2.0'),
      downloadUrl: Uri.parse('https://models.example.org/voice.bin'),
      sha256: manifest().sha256,
      compressedBytes: 3,
    );

    await expectLater(
      service.install(
        invalid,
        downloadsEnabled: true,
        availableStorageBytes: 100,
      ),
      throwsA(isA<VoicePackInstallException>()),
    );
    expect(await database.loadVoicePackInstall('../outside'), isNull);
  });

  test('rejects path traversal in remote version metadata', () async {
    final unsafeVersion = VoicePackManifest(
      id: 'org.example.voice',
      displayName: 'Unsafe Version',
      version: '../../outside',
      locale: 'en',
      licenseId: 'Apache-2.0',
      licenseUrl: Uri.parse('https://licenses.example.org/apache-2.0'),
      downloadUrl: Uri.parse('https://models.example.org/voice.bin'),
      sha256: manifest().sha256,
      compressedBytes: 3,
    );
    await expectLater(
      service.install(
        unsafeVersion,
        downloadsEnabled: true,
        availableStorageBytes: 100,
      ),
      throwsA(isA<VoicePackInstallException>()),
    );
    expect(await database.loadVoicePackInstall('org.example.voice'), isNull);
    expect(await Directory(p.join(temp.path, 'outside')).exists(), isFalse);
  });

  test('only accepts the app-owned content-addressed install layout', () {
    final root = p.join(temp.path, 'voice_packs');
    final valid = p.join(
      root,
      'org.example.voice',
      '1.0.0',
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      'model.bin',
    );
    expect(
      VoicePackStorageService.isSafeInstalledVoicePackPath(
        rootDirectory: root,
        packId: 'org.example.voice',
        installPath: valid,
      ),
      isTrue,
    );
    for (final invalid in [
      p.join(temp.path, 'outside.bin'),
      p.join(root, 'org.example.voice', '1.0.0', 'bad-digest', 'model.bin'),
      p.join(root, 'org.example.other', '1.0.0',
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 'model.bin'),
      p.join(root, 'org.example.voice', '1.0.0',
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 'settings.json'),
    ]) {
      expect(
        VoicePackStorageService.isSafeInstalledVoicePackPath(
          rootDirectory: root,
          packId: 'org.example.voice',
          installPath: invalid,
        ),
        isFalse,
        reason: 'Must reject unsafe path: $invalid',
      );
    }
  });
}
