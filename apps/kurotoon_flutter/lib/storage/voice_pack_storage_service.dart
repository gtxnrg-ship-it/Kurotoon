import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../storage/kurotoon_database.dart';

class VoicePackInstallException implements Exception {
  const VoicePackInstallException(this.message);

  final String message;

  @override
  String toString() => 'VoicePackInstallException: $message';
}

class _VoicePackDigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest event) => value = event;

  @override
  void close() {}
}

/// Downloads licensed voice assets as files, verifies them incrementally, and
/// only publishes a pack to SQLite after the complete file passes SHA-256.
class VoicePackStorageService {
  VoicePackStorageService({
    required this.database,
    HttpClient? client,
    Directory? rootDirectory,
    this.requestTimeout = const Duration(seconds: 20),
    this.policy = const VoicePackPolicy(),
  })  : _client = client ?? HttpClient(),
        _rootDirectory = rootDirectory;

  final KurotoonDatabase database;
  final HttpClient _client;
  final Directory? _rootDirectory;
  final Duration requestTimeout;
  final VoicePackPolicy policy;
  bool _disposed = false;

  Future<Directory> _root() async {
    final root = _rootDirectory ?? Directory(
      path.join((await getApplicationSupportDirectory()).path, 'voice_packs'),
    );
    await root.create(recursive: true);
    return root;
  }

  Future<String> install(
    VoicePackManifest pack, {
    required bool downloadsEnabled,
    required int availableStorageBytes,
  }) async {
    if (_disposed) throw StateError('Voice-pack storage service is disposed.');
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{2,127}$').hasMatch(pack.id)) {
      throw const VoicePackInstallException('Voice-pack ID is invalid.');
    }
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9.+_-]{0,63}$').hasMatch(pack.version)) {
      throw const VoicePackInstallException('Voice-pack version is invalid.');
    }
    final decision = policy.validate(
      pack,
      downloadsEnabled: downloadsEnabled,
      availableStorageBytes: availableStorageBytes,
    );
    if (!decision.allowed) throw VoicePackInstallException(decision.reason);
    await _validateResolvedAddresses(pack.downloadUrl.host);

    final root = await _root();
    final packDirectory = Directory(path.join(root.path, pack.id, pack.version, pack.sha256.toLowerCase()));
    await packDirectory.create(recursive: true);
    final target = File(path.join(packDirectory.path, 'model.bin'));

    // Reuse an already verified copy rather than downloading the same model again.
    if (await target.exists() &&
        await const VoicePackVerifier().verifyStream(target.openRead(), pack.sha256)) {
      await _recordInstall(pack, target.path);
      return target.path;
    }

    final temporary = File(path.join(
      packDirectory.path,
      '.model-${DateTime.now().microsecondsSinceEpoch}.pending',
    ));
    var installedNewFile = false;
    var metadataCommitted = false;
    try {
      await _downloadAndVerify(pack, temporary);
      // The target is content-addressed. If it existed, it failed verification;
      // remove only that exact managed target before atomically publishing.
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
      installedNewFile = true;

      final prior = await database.loadVoicePackInstall(pack.id);
      await _recordInstall(pack, target.path);
      metadataCommitted = true;

      final priorPath = prior?['install_path'];
      if (priorPath is String &&
          priorPath != target.path &&
          isSafeInstalledVoicePackPath(
            rootDirectory: root.path,
            packId: pack.id,
            installPath: priorPath,
          )) {
        try {
          final oldFile = File(priorPath);
          if (await oldFile.exists()) await oldFile.delete();
        } on FileSystemException {
          // A leftover old model is an orphan; the committed new install stays valid.
        }
      }
      return target.path;
    } catch (_) {
      if (installedNewFile && !metadataCommitted && await target.exists()) {
        try {
          await target.delete();
        } on FileSystemException {
          // Keep the original failure; an unindexed file can be cleaned later.
        }
      }
      rethrow;
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } on FileSystemException {
          // Temporary downloads are disposable and can be cleaned on next launch.
        }
      }
    }
  }

  Future<void> _recordInstall(VoicePackManifest pack, String installPath) =>
      database.recordVoicePackInstall(
        packId: pack.id,
        version: pack.version,
        locale: pack.locale,
        licenseId: pack.licenseId,
        sha256: pack.sha256,
        installPath: installPath,
      );

  Future<void> _downloadAndVerify(VoicePackManifest pack, File temporary) async {
    HttpClientRequest? request;
    RandomAccessFile? output;
    final digest = _VoicePackDigestSink();
    final digestSink = sha256.startChunkedConversion(digest);
    var totalBytes = 0;
    try {
      request = await _client.getUrl(pack.downloadUrl).timeout(requestTimeout);
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
      request.headers.set(HttpHeaders.userAgentHeader, 'KuroToon/0.1 voice-pack-client');
      final response = await request.close().timeout(requestTimeout);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        response.detachSocket().then((socket) => socket.destroy());
        throw const VoicePackInstallException('Voice-pack server redirected; use the final HTTPS URL.');
      }
      if (response.statusCode != HttpStatus.ok) {
        response.detachSocket().then((socket) => socket.destroy());
        throw VoicePackInstallException('Voice-pack server returned HTTP ${response.statusCode}.');
      }
      if (response.contentLength > pack.compressedBytes ||
          response.contentLength > policy.maxPackBytes) {
        response.detachSocket().then((socket) => socket.destroy());
        throw const VoicePackInstallException('Voice-pack response exceeds its declared size limit.');
      }

      output = await temporary.open(mode: FileMode.write);
      await for (final chunk in response.timeout(requestTimeout)) {
        totalBytes += chunk.length;
        if (totalBytes > pack.compressedBytes || totalBytes > policy.maxPackBytes) {
          request.abort();
          throw const VoicePackInstallException('Voice-pack download exceeded its size limit.');
        }
        digestSink.add(chunk);
        await output.writeFrom(chunk);
      }
      digestSink.close();
      await output.flush();
      await output.close();
      output = null;

      if (totalBytes != pack.compressedBytes) {
        throw const VoicePackInstallException('Voice-pack byte count does not match its manifest.');
      }
      if (digest.value?.toString().toLowerCase() != pack.sha256.toLowerCase()) {
        throw const VoicePackInstallException('Voice-pack SHA-256 verification failed.');
      }
    } on TimeoutException {
      request?.abort();
      throw const VoicePackInstallException('Voice-pack download timed out.');
    } finally {
      if (output != null) await output.close();
    }
  }

  Future<void> _validateResolvedAddresses(String host) async {
    final addresses = await InternetAddress.lookup(host).timeout(requestTimeout);
    if (addresses.isEmpty || addresses.any(_isNonPublic)) {
      throw const VoicePackInstallException('Voice-pack hostname resolves to a non-public address.');
    }
  }

  bool _isNonPublic(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      final a = bytes[0], b = bytes[1], c = bytes[2];
      final carrierGradeNat = a == 100 && b >= 64 && b <= 127;
      final linkLocal = a == 169 && b == 254;
      final private172 = a == 172 && b >= 16 && b <= 31;
      final reserved192 = a == 192 && (b == 168 || (b == 0 && (c == 0 || c == 2)));
      final reserved198 = a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100));
      final reserved203 = a == 203 && b == 0 && c == 113;
      return a == 0 || a == 10 || a == 127 || a >= 224 ||
          carrierGradeNat || linkLocal || private172 ||
          reserved192 || reserved198 || reserved203;
    }
    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
      final allZero = bytes.every((byte) => byte == 0);
      final loopback = bytes.take(15).every((byte) => byte == 0) && bytes[15] == 1;
      final uniqueLocal = (bytes[0] & 0xfe) == 0xfc;
      final linkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80;
      final multicast = bytes[0] == 0xff;
      final ipv4Mapped = bytes.take(10).every((byte) => byte == 0) && bytes[10] == 0xff && bytes[11] == 0xff;
      return allZero || loopback || uniqueLocal || linkLocal || multicast || ipv4Mapped;
    }
    return true;
  }

  Future<void> uninstall(String packId) async {
    if (_disposed) throw StateError('Voice-pack storage service is disposed.');
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{2,127}$').hasMatch(packId)) {
      throw ArgumentError.value(packId, 'packId', 'Invalid voice-pack identifier.');
    }
    final prior = await database.loadVoicePackInstall(packId);
    await database.removeVoicePackInstall(packId);
    final installPath = prior?['install_path'];
    if (installPath is! String) return;
    final root = await _root();
    if (!isSafeInstalledVoicePackPath(
      rootDirectory: root.path,
      packId: packId,
      installPath: installPath,
    )) {
      // Never follow a path from SQLite outside the app-owned pack directory.
      return;
    }
    final file = File(installPath);
    if (await file.exists()) await file.delete();
  }

  static bool isSafeInstalledVoicePackPath({
    required String rootDirectory,
    required String packId,
    required String installPath,
  }) {
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{2,127}$').hasMatch(packId)) return false;
    final root = path.normalize(path.absolute(rootDirectory));
    final packRoot = path.normalize(path.absolute(path.join(root, packId)));
    final candidate = path.normalize(path.absolute(installPath));
    if (path.basename(candidate) != 'model.bin' || !path.isWithin(packRoot, candidate)) return false;
    final segments = path.split(path.relative(candidate, from: packRoot));
    return segments.length == 3 &&
        RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9.+_-]{0,63}$').hasMatch(segments[0]) &&
        RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(segments[1]) &&
        segments[2] == 'model.bin';
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.close(force: true);
  }
}
