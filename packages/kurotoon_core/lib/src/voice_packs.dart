import 'package:crypto/crypto.dart';

import 'repository_policy.dart';

class VoicePackManifest {
  VoicePackManifest({
    required this.id,
    required this.displayName,
    required this.version,
    required this.locale,
    required this.licenseId,
    required this.licenseUrl,
    required this.downloadUrl,
    required this.sha256,
    required this.compressedBytes,
    this.attribution,
    this.sourceName,
  }) {
    if (id.trim().isEmpty || displayName.trim().isEmpty || version.trim().isEmpty) {
      throw ArgumentError('Voice pack requires an id, display name, and version.');
    }
  }

  final String id;
  final String displayName;
  final String version;
  final String locale;
  final String licenseId;
  final Uri licenseUrl;
  final Uri downloadUrl;
  final String sha256;
  final int compressedBytes;
  final String? attribution;
  final String? sourceName;

  bool get attributionRequired => licenseId == 'CC-BY-4.0';
}

class VoicePackDecision {
  const VoicePackDecision({required this.allowed, required this.reason});

  final bool allowed;
  final String reason;
}

class VoicePackPolicy {
  const VoicePackPolicy({
    this.maxPackBytes = 536870912,
    this.allowedLicenses = const {
      'MIT',
      'Apache-2.0',
      'BSD-3-Clause',
      'CC0-1.0',
      'CC-BY-4.0',
    },
  });

  /// Per-pack ceiling is 512 MiB; the global cache budget remains separately enforced.
  final int maxPackBytes;
  final Set<String> allowedLicenses;

  VoicePackDecision validate(
    VoicePackManifest pack, {
    required bool downloadsEnabled,
    required int availableStorageBytes,
  }) {
    if (!downloadsEnabled) {
      return const VoicePackDecision(allowed: false, reason: 'Voice-pack downloads are disabled');
    }
    if (!allowedLicenses.contains(pack.licenseId)) {
      return const VoicePackDecision(allowed: false, reason: 'Voice-pack license is not on the approved allowlist');
    }
    const urlPolicy = RepositoryPolicy();
    if (!urlPolicy.validate(pack.downloadUrl.toString()).allowed ||
        !urlPolicy.validate(pack.licenseUrl.toString()).allowed) {
      return const VoicePackDecision(allowed: false, reason: 'Download and license links must use public HTTPS URLs');
    }
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(pack.sha256)) {
      return const VoicePackDecision(allowed: false, reason: 'A valid SHA-256 digest is required');
    }
    if (pack.compressedBytes <= 0 || pack.compressedBytes > maxPackBytes) {
      return const VoicePackDecision(allowed: false, reason: 'Voice pack exceeds the per-pack size limit');
    }
    if (pack.compressedBytes > availableStorageBytes) {
      return const VoicePackDecision(allowed: false, reason: 'Insufficient available storage for this pack');
    }
    if (pack.attributionRequired && (pack.attribution == null || pack.attribution!.trim().isEmpty)) {
      return const VoicePackDecision(allowed: false, reason: 'This license requires attribution');
    }
    return const VoicePackDecision(allowed: true, reason: 'Manifest passed metadata and storage checks');
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest event) => value = event;

  @override
  void close() {}
}

class VoicePackVerifier {
  const VoicePackVerifier();

  /// Hashes the stream incrementally, so a large model is never copied into one
  /// giant in-memory byte array merely to verify its checksum.
  Future<bool> verifyStream(Stream<List<int>> chunks, String expectedSha256) async {
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expectedSha256)) return false;
    final sink = _DigestSink();
    final digestSink = sha256.startChunkedConversion(sink);
    await for (final chunk in chunks) {
      digestSink.add(chunk);
    }
    digestSink.close();
    return sink.value?.toString().toLowerCase() == expectedSha256.toLowerCase();
  }

  bool verifyBytes(List<int> bytes, String expectedSha256) {
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expectedSha256)) return false;
    return sha256.convert(bytes).toString().toLowerCase() == expectedSha256.toLowerCase();
  }
}
