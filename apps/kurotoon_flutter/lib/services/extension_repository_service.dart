import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../storage/kurotoon_database.dart';

class RepositoryPreview {
  const RepositoryPreview({
    required this.indexUri,
    required this.index,
    required this.indexDigest,
  });

  final Uri indexUri;
  final ExtensionRepositoryIndex index;
  final String indexDigest;
}

class ExtensionRepositoryService implements DeclarativeJsonFetcher {
  ExtensionRepositoryService({
    required this.database,
    HttpClient? client,
    this.requestTimeout = const Duration(seconds: 12),
    this.maxIndexBytes = 2 * 1024 * 1024,
    this.maxManifestBytes = 2 * 1024 * 1024,
  }) : _client = client ?? HttpClient() {
    _client.connectionTimeout = requestTimeout;
    _client.idleTimeout = const Duration(seconds: 15);
    _client.maxConnectionsPerHost = 4;
  }

  final KurotoonDatabase database;
  final HttpClient _client;
  final Duration requestTimeout;
  final int maxIndexBytes;
  final int maxManifestBytes;

  Future<RepositoryPreview> previewRepository(String rawUrl) async {
    final decision = const RepositoryPolicy().validate(rawUrl);
    if (!decision.allowed || decision.uri == null) throw FormatException(decision.reason);
    final indexUri = decision.uri!;
    final bytes = await _getBytes(indexUri, maxBytes: maxIndexBytes);
    final index = RepositoryIndexValidator(maxIndexBytes: maxIndexBytes).parse(
      body: utf8.decode(bytes, allowMalformed: false),
      indexUri: indexUri,
    );
    return RepositoryPreview(indexUri: indexUri, index: index, indexDigest: _sha256Of(bytes));
  }

  /// Call only after the UI has shown the repository identity and obtained confirmation.
  /// The index is fetched again so a stale preview cannot silently approve changed metadata.
  Future<ExtensionRepositoryIndex> addRepository(String rawUrl, {String? expectedPreviewDigest}) async {
    final preview = await previewRepository(rawUrl);
    if (expectedPreviewDigest != null && preview.indexDigest != expectedPreviewDigest) {
      throw const FormatException('Repository changed after preview. Review the new index before adding it.');
    }
    final index = preview.index;
    await database.saveExtensionRepository(
      ExtensionRepository(
        id: index.id,
        name: index.name,
        indexUri: preview.indexUri,
        description: index.description,
        website: index.website,
        trust: RepositoryTrust.userAdded,
      ),
      indexDigest: preview.indexDigest,
    );
    return index;
  }

  Future<ExtensionRepositoryIndex> refreshRepository(Uri indexUri) async {
    final bytes = await _getBytes(indexUri, maxBytes: maxIndexBytes);
    final index = RepositoryIndexValidator(maxIndexBytes: maxIndexBytes).parse(
      body: utf8.decode(bytes, allowMalformed: false),
      indexUri: indexUri,
    );
    await database.markRepositoryChecked(index.id, indexDigest: _sha256Of(bytes));
    return index;
  }

  Future<String> installDeclarativeExtension({
    required ExtensionPackageEntry entry,
    required String repositoryId,
  }) async {
    final bytes = await _getBytes(entry.manifestUri, maxBytes: maxManifestBytes);
    const ExtensionPackageVerifier(maxPackageBytes: 2 * 1024 * 1024).verify(
      bytes: bytes,
      entry: entry,
    );
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map) throw const FormatException('Extension manifest must be a JSON object.');
    final manifest = parseDeclarativeExtensionManifest(Map<String, Object?>.from(decoded));
    if (manifest.id != entry.id || manifest.version != entry.version ||
        manifest.minimumAppApi != entry.minimumAppApi ||
        !manifest.capabilities.containsAll(entry.capabilities)) {
      throw const FormatException('Extension manifest does not match its repository index entry.');
    }

    final root = await getApplicationSupportDirectory();
    final targetDirectory = Directory(path.join(root.path, 'extensions', manifest.id, manifest.version));
    await targetDirectory.create(recursive: true);
    final target = File(path.join(targetDirectory.path, 'manifest.json'));
    final temp = File(path.join(
      targetDirectory.path,
      '.manifest-' + DateTime.now().microsecondsSinceEpoch.toString() + '.tmp',
    ));
    try {
      await temp.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }

    await database.recordInstalledExtension(
      entry: entry,
      repositoryId: repositoryId,
      installPath: target.path,
      enabled: false,
    );
    return target.path;
  }

  Future<void> uninstallExtension(String extensionId) async {
    final rows = await database.loadInstalledExtensions();
    Map<String, Object?>? row;
    for (final item in rows) {
      if (item['extension_id'] == extensionId) {
        row = item;
        break;
      }
    }
    if (row != null && row['install_path'] is String) {
      final file = File(row['install_path'] as String);
      if (await file.exists()) await file.delete();
      final versionDirectory = file.parent;
      if (await versionDirectory.exists() && await versionDirectory.list().isEmpty) {
        await versionDirectory.delete();
      }
      final idDirectory = versionDirectory.parent;
      if (await idDirectory.exists() && await idDirectory.list().isEmpty) await idDirectory.delete();
    }
    await database.removeInstalledExtension(extensionId);
  }

  @override
  Future<Object?> getJson(
    Uri uri, {
    required CancellationToken cancellationToken,
    required int maxResponseBytes,
  }) async {
    final bytes = await _getBytes(
      uri,
      maxBytes: maxResponseBytes,
      cancellationToken: cancellationToken,
    );
    cancellationToken.throwIfCancelled();
    return jsonDecode(utf8.decode(bytes, allowMalformed: false));
  }

  Future<List<int>> _getBytes(
    Uri uri, {
    required int maxBytes,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    _validatePublicHttps(uri);
    await _validateResolvedAddresses(uri.host);
    HttpClientRequest? request;
    void Function()? detach;
    try {
      final activeRequest = await _client.getUrl(uri).timeout(requestTimeout);
      request = activeRequest;
      activeRequest.followRedirects = false;
      activeRequest.maxRedirects = 0;
      activeRequest.headers.set(HttpHeaders.acceptHeader, 'application/json');
      activeRequest.headers.set(HttpHeaders.userAgentHeader, 'KuroToon/0.1 repository-client');
      detach = cancellationToken?.onCancel((_) => activeRequest.abort());
      cancellationToken?.throwIfCancelled();
      final response = await activeRequest.close().timeout(requestTimeout);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw HttpException('Repository redirects are not followed; add the final HTTPS URL instead.', uri: uri);
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Repository returned HTTP ' + response.statusCode.toString() + '.', uri: uri);
      }
      if (response.contentLength > maxBytes) {
        response.detachSocket().then((socket) => socket.destroy());
        throw HttpException('Repository response exceeds the configured size limit.', uri: uri);
      }
      final result = <int>[];
      await for (final chunk in response.timeout(requestTimeout)) {
        cancellationToken?.throwIfCancelled();
        if (result.length + chunk.length > maxBytes) {
          activeRequest.abort();
          throw HttpException('Repository response exceeded the configured size limit.', uri: uri);
        }
        result.addAll(chunk);
      }
      cancellationToken?.throwIfCancelled();
      return result;
    } on TimeoutException {
      request?.abort();
      rethrow;
    } on Object {
      if (cancellationToken?.isCancelled == true) {
        throw OperationCancelled(cancellationToken!.reason);
      }
      rethrow;
    } finally {
      detach?.call();
    }
  }

  void _validatePublicHttps(Uri uri) {
    final decision = const RepositoryPolicy().validate(uri.toString());
    if (!decision.allowed) throw FormatException(decision.reason);
  }

  Future<void> _validateResolvedAddresses(String host) async {
    final addresses = await InternetAddress.lookup(host).timeout(requestTimeout);
    if (addresses.isEmpty || addresses.any(_isNonPublic)) {
      throw const HttpException('Repository hostname resolved to a non-public address.');
    }
  }

  bool _isNonPublic(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      final a = bytes[0], b = bytes[1], c = bytes[2];
      return a == 0 || a == 10 || a == 127 || a >= 224 ||
          (a == 100 && b >= 64 && b <= 127) ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && (b == 168 || (b == 0 && c == 0) || (b == 0 && c == 2))) ||
          (a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100))) ||
          (a == 203 && b == 0 && c == 113);
    }
    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
      final allZero = bytes.every((byte) => byte == 0);
      final loopback = bytes.take(15).every((byte) => byte == 0) && bytes[15] == 1;
      final uniqueLocal = (bytes[0] & 0xfe) == 0xfc;
      final linkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80;
      final multicast = bytes[0] == 0xff;
      return allZero || loopback || uniqueLocal || linkLocal || multicast;
    }
    return true;
  }

  String _sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

  void dispose() => _client.close(force: true);
}
