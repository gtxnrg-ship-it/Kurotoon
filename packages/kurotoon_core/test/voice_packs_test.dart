import 'dart:convert';

import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

VoicePackManifest pack({
  String licenseId = 'Apache-2.0',
  String sha = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
  int bytes = 3,
  String? attribution,
}) => VoicePackManifest(
      id: 'en-neutral',
      displayName: 'English Neutral',
      version: '1',
      locale: 'en',
      licenseId: licenseId,
      licenseUrl: Uri.parse('https://licenses.example.org/$licenseId'),
      downloadUrl: Uri.parse('https://models.example.org/en-neutral.bin'),
      sha256: sha,
      compressedBytes: bytes,
      attribution: attribution,
      sourceName: 'Open voice project',
    );

void main() {
  const policy = VoicePackPolicy();

  test('requires explicit download opt-in and respects space/size constraints', () {
    expect(
      policy.validate(pack(), downloadsEnabled: false, availableStorageBytes: 100).allowed,
      isFalse,
    );
    expect(
      policy.validate(pack(bytes: 101), downloadsEnabled: true, availableStorageBytes: 100).allowed,
      isFalse,
    );
    expect(
      policy.validate(pack(), downloadsEnabled: true, availableStorageBytes: 3).allowed,
      isTrue,
    );
  });

  test('requires attribution for attribution-based voice-pack licenses', () {
    expect(
      policy.validate(
        pack(licenseId: 'CC-BY-4.0'),
        downloadsEnabled: true,
        availableStorageBytes: 3,
      ).allowed,
      isFalse,
    );
    expect(
      policy.validate(
        pack(licenseId: 'CC-BY-4.0', attribution: 'Voice models by Example Project'),
        downloadsEnabled: true,
        availableStorageBytes: 3,
      ).allowed,
      isTrue,
    );
  });

  test('verifies data incrementally without requiring one huge byte buffer', () async {
    const verifier = VoicePackVerifier();
    final stream = Stream<List<int>>.fromIterable([
      utf8.encode('a'),
      utf8.encode('b'),
      utf8.encode('c'),
    ]);
    expect(
      await verifier.verifyStream(
        stream,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      ),
      isTrue,
    );
    expect(verifier.verifyBytes(utf8.encode('wrong'), pack().sha256), isFalse);
  });
}
