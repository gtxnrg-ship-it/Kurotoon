import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../storage/kurotoon_database.dart';

/// Validates persisted install paths before deleting extension files.
///
/// A database row is not trusted as a filesystem capability: it may be stale,
/// corrupted, or modified. Only a manifest inside the app-owned extension
/// directory for the exact extension ID may be removed.
class ExtensionInstallPathPolicy {
  const ExtensionInstallPathPolicy._();

  static bool isSafeManifestPath({
    required String extensionsRoot,
    required String extensionId,
    required String manifestPath,
  }) {
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{2,127}$').hasMatch(extensionId)) {
      return false;
    }
    final root = path.normalize(path.absolute(extensionsRoot));
    final expectedExtensionRoot = path.normalize(path.absolute(path.join(root, extensionId)));
    final candidate = path.normalize(path.absolute(manifestPath));
    if (path.basename(candidate) != 'manifest.json' ||
        !path.isWithin(expectedExtensionRoot, candidate)) {
      return false;
    }
    // Installed layout is extensions/<id>/<version>/<digest>/manifest.json.
    final relative = path.relative(candidate, from: expectedExtensionRoot);
    final segments = path.split(relative);
    return segments.length == 3 &&
        segments[0].isNotEmpty &&
        segments[1].isNotEmpty &&
        RegExp(r'^[a-fA-F0-9]{12}$').hasMatch(segments[1]) &&
        segments[2] == 'manifest.json';
  }

  /// Also rejects symlinks in every path segment. Lexical path validation is
  /// not sufficient when a directory inside the extension root can be a link.
  static Future<bool> isSafeManifestPathOnDisk({
    required String extensionsRoot,
    required String extensionId,
    required String manifestPath,
  }) async {
    if (!isSafeManifestPath(
      extensionsRoot: extensionsRoot,
      extensionId: extensionId,
      manifestPath: manifestPath,
    )) {
      return false;
    }
    final root = path.normalize(path.absolute(extensionsRoot));
    final candidate = path.normalize(path.absolute(manifestPath));
    if (await FileSystemEntity.type(root, followLinks: false) == FileSystemEntityType.link) {
      return false;
    }
    var current = root;
    for (final segment in path.split(path.relative(candidate, from: root))) {
      current = path.join(current, segment);
      if (await FileSystemEntity.type(current, followLinks: false) == FileSystemEntityType.link) {
        return false;
      }
    }
    return true;
  }
}

class ExtensionRecoveryReport {
  const ExtensionRecoveryReport({
    this.operationsRecovered = 0,
    this.installRecordsCompleted = 0,
    this.uninstallRecordsCompleted = 0,
    this.temporaryFilesRemoved = 0,
    this.orphanManifestsRemoved = 0,
    this.failures = 0,
  });

  final int operationsRecovered;
  final int installRecordsCompleted;
  final int uninstallRecordsCompleted;
  final int temporaryFilesRemoved;
  final int orphanManifestsRemoved;
  final int failures;

  bool get complete => failures == 0;
  bool get changed => operationsRecovered + installRecordsCompleted + uninstallRecordsCompleted + temporaryFilesRemoved + orphanManifestsRemoved > 0;
}

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
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _client = client ?? HttpClient(),
       _supportDirectoryProvider = supportDirectoryProvider {
    _client.connectionTimeout = requestTimeout;
    _client.idleTimeout = const Duration(seconds: 15);
    _client.maxConnectionsPerHost = 4;
  }

  final KurotoonDatabase database;
  final HttpClient _client;
  final Duration requestTimeout;
  final int maxIndexBytes;
  final int maxManifestBytes;
  final Future<Directory> Function()? _supportDirectoryProvider;
  ExtensionRecoveryReport _lastRecoveryReport = const ExtensionRecoveryReport();

  ExtensionRecoveryReport get lastRecoveryReport => _lastRecoveryReport;

  Future<Directory> _supportDirectory() async =>
      await _supportDirectoryProvider?.call() ?? getApplicationSupportDirectory();

  /// Inspects a Mihon/Tachiyomi index without installing or executing packages.
  /// Supports protobuf index.pb and legacy index.json/index.min.json catalogs.
  Future<MihonRepositoryIndex> previewMihonCatalog(
    String rawUrl, {
    int previewLimit = 50,
  }) async {
    if (previewLimit < 1 || previewLimit > 100) {
      throw ArgumentError.value(previewLimit, 'previewLimit', 'Must be between 1 and 100.');
    }
    const maxMetadataEntries = 10000;
    final decision = const RepositoryPolicy().validate(rawUrl);
    if (!decision.allowed || decision.uri == null) throw FormatException(decision.reason);
    final uri = RepositoryMarkdownDiscovery().normalizeGitHubFileUrl(decision.uri!);
    final lowerPath = uri.path.toLowerCase();
    final bytes = await _getBytes(uri, maxBytes: 4 * 1024 * 1024);
    MihonRepositoryIndex index;
    if (lowerPath.endsWith('.pb')) {
      index = MihonRepositoryIndex.parse(
        bytes,
        indexUri: uri,
        maxBytes: 4 * 1024 * 1024,
        maxExtensions: maxMetadataEntries,
      );
    } else if (lowerPath.endsWith('.json')) {
      index = MihonRepositoryIndex.parseJson(
        bytes,
        indexUri: uri,
        maxBytes: 4 * 1024 * 1024,
        maxExtensions: maxMetadataEntries,
      );
    } else {
      throw const FormatException('Use a direct index.pb, index.json, or index.min.json URL.');
    }

    final listUri = index.extensionListUrl;
    if (listUri != null) {
      if (listUri.host.toLowerCase() != uri.host.toLowerCase()) {
        throw const FormatException('External Mihon extension lists must stay on the same host as the repository index.');
      }
      final listBytes = await _getBytes(listUri, maxBytes: 16 * 1024 * 1024);
      final extensions = MihonRepositoryIndex.parseExtensionList(
        listBytes,
        maxBytes: 16 * 1024 * 1024,
        maxExtensions: maxMetadataEntries,
      );
      index = MihonRepositoryIndex(
        name: index.name,
        badgeLabel: index.badgeLabel,
        signingKey: index.signingKey,
        contact: index.contact,
        extensionListUrl: listUri,
        extensions: extensions,
      );
    }

    // Catalog previews are UI only. Keep metadata counts accurate while
    // retaining a small sample so large indexes do not create thousands of rows.
    return boundedMihonRepositoryPreview(index, limit: previewLimit);
  }

  Future<RepositoryPreview> previewRepository(String rawUrl) async {
    final decision = const RepositoryPolicy().validate(rawUrl);
    if (!decision.allowed || decision.uri == null) throw FormatException(decision.reason);
    const discovery = RepositoryMarkdownDiscovery();
    final suppliedUri = discovery.normalizeGitHubFileUrl(decision.uri!);
    if (suppliedUri.path.toLowerCase().endsWith('.json')) {
      return _previewIndex(suppliedUri);
    }

    final readme = discovery.readmeCandidate(rawUrl);
    if (readme == null) {
      throw const FormatException(
        'Paste a direct HTTPS index.json URL, a public GitHub repository URL, or a README.md URL.',
      );
    }

    // GitHub repository roots may use either default branch name. Explicit
    // README URLs are tried exactly as supplied by the discovery helper.
    final readmeCandidates = <Uri>[readme];
    if (suppliedUri.host.toLowerCase() == 'github.com' &&
        suppliedUri.pathSegments.where((part) => part.isNotEmpty).length == 2) {
      readmeCandidates.add(Uri.https(
        'raw.githubusercontent.com',
        '/${suppliedUri.pathSegments.where((part) => part.isNotEmpty).elementAt(0)}/'
        '${suppliedUri.pathSegments.where((part) => part.isNotEmpty).elementAt(1)}/master/README.md',
      ));
    }

    Object? lastFailure;
    for (final readmeUri in readmeCandidates) {
      try {
        final markdownBytes = await _getBytes(readmeUri, maxBytes: maxIndexBytes);
        final markdown = utf8.decode(markdownBytes, allowMalformed: false);
        final links = discovery.indexLinks(markdown, documentUri: readmeUri);
        for (final candidate in links.take(12)) {
          try {
            // Each discovered URL passes the same HTTPS, DNS, size, schema,
            // and same-origin resource checks as a manually entered index.
            return await _previewIndex(candidate);
          } on Object catch (error) {
            lastFailure = error;
          }
        }
      } on Object catch (error) {
        lastFailure = error;
      }
    }
    if (lastFailure != null) {
      throw FormatException(
        'README discovery did not find a valid KuroToon JSON index. '
        'Mihon/Tachiyomi protobuf indexes and APK/JAR extensions are not executable providers in KuroToon.',
      );
    }
    throw const FormatException(
      'No JSON index links were found in this README. The repository must publish a KuroToon-compatible schemaVersion 1 index and declarative JSON manifests.',
    );
  }

  Future<RepositoryPreview> _previewIndex(Uri indexUri) async {
    final decision = const RepositoryPolicy().validate(indexUri.toString());
    if (!decision.allowed || decision.uri == null) throw FormatException(decision.reason);
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

  Future<ExtensionRepositoryIndex> loadRepositoryIndex(String repositoryId) async {
    final rows = await database.loadExtensionRepositories();
    Map<String, Object?>? row;
    for (final item in rows) {
      if (item['id'] == repositoryId) {
        row = item;
        break;
      }
    }
    if (row == null || row['index_url'] is! String) {
      throw StateError('Repository is not installed.');
    }
    final uri = Uri.tryParse(row['index_url'] as String);
    if (uri == null) throw const FormatException('Stored repository URL is invalid.');
    final index = await refreshRepository(uri);
    if (index.id != repositoryId) {
      throw const FormatException('Repository identity changed. Remove and add the repository again after review.');
    }
    return index;
  }

  Future<String> installExtensionById({
    required String repositoryId,
    required String extensionId,
  }) async {
    final index = await loadRepositoryIndex(repositoryId);
    ExtensionPackageEntry? selected;
    for (final entry in index.extensions) {
      if (entry.id == extensionId) {
        selected = entry;
        break;
      }
    }
    if (selected == null) throw StateError('This extension is not listed in the selected repository.');
    return _installDeclarativeExtension(entry: selected, repositoryId: repositoryId);
  }

  Future<ExtensionRepositoryIndex> refreshRepository(Uri indexUri) async {
    final bytes = await _getBytes(indexUri, maxBytes: maxIndexBytes);
    final index = RepositoryIndexValidator(maxIndexBytes: maxIndexBytes).parse(
      body: utf8.decode(bytes, allowMalformed: false),
      indexUri: indexUri,
    );
    final savedRepositories = await database.loadExtensionRepositories();
    final registered = savedRepositories.any((row) =>
        row['id'] == index.id && row['index_url'] == indexUri.toString());
    if (!registered) {
      throw const FormatException('Repository identity or URL does not match a saved repository.');
    }
    await database.markRepositoryChecked(index.id, indexDigest: _sha256Of(bytes));
    return index;
  }

  Future<String> _installDeclarativeExtension({
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
        manifest.capabilities.length != entry.capabilities.length ||
        !manifest.capabilities.containsAll(entry.capabilities)) {
      throw const FormatException('Extension manifest does not match its repository index entry.');
    }

    final installedRows = await database.loadInstalledExtensions();
    String? previousPath;
    var previousEnabled = false;
    for (final row in installedRows) {
      if (row['extension_id'] == entry.id && row['install_path'] is String) {
        previousPath = row['install_path'] as String;
        previousEnabled = row['enabled'] == 1;
        break;
      }
    }
    final root = await getApplicationSupportDirectory();
    final extensionsRoot = path.join(root.path, 'extensions');
    final targetDirectory = Directory(path.join(
      extensionsRoot,
      manifest.id,
      manifest.version,
      entry.sha256.substring(0, 12),
    ));
    final target = File(path.join(targetDirectory.path, 'manifest.json'));
    if (!await ExtensionInstallPathPolicy.isSafeManifestPathOnDisk(
      extensionsRoot: extensionsRoot,
      extensionId: manifest.id,
      manifestPath: target.path,
    )) {
      throw StateError('Refusing to install into an unsafe extension path.');
    }
    await targetDirectory.create(recursive: true);
    if (!await ExtensionInstallPathPolicy.isSafeManifestPathOnDisk(
      extensionsRoot: extensionsRoot,
      extensionId: manifest.id,
      manifestPath: target.path,
    )) {
      throw StateError('Extension path became unsafe during directory creation.');
    }
    final temp = File(path.join(
      targetDirectory.path,
      '.manifest-' + DateTime.now().microsecondsSinceEpoch.toString() + '.tmp',
    ));
    var createdTarget = false;
    try {
      if (await FileSystemEntity.type(temp.path, followLinks: false) != FileSystemEntityType.notFound) {
        throw StateError('A temporary extension manifest path already exists.');
      }
      await temp.writeAsBytes(bytes, flush: true);
      if (!await ExtensionInstallPathPolicy.isSafeManifestPathOnDisk(
        extensionsRoot: extensionsRoot,
        extensionId: manifest.id,
        manifestPath: target.path,
      )) {
        throw StateError('Extension path became unsafe before manifest install.');
      }
      if (!await target.exists()) {
        await temp.rename(target.path);
        createdTarget = true;
      }
    } finally {
      if (await temp.exists()) await temp.delete();
    }

    try {
      await database.recordInstalledExtension(
        entry: entry,
        repositoryId: repositoryId,
        installPath: target.path,
        enabled: previousEnabled,
      );
    } catch (_) {
      if (createdTarget && await target.exists()) await target.delete();
      rethrow;
    }
    if (previousPath != null && previousPath != target.path) {
      // A stale install path is not a filesystem capability. Leave an invalid
      // path untouched for later diagnostics instead of deleting outside root.
      if (await isSafeInstalledManifestPath(
        extensionId: entry.id,
        manifestPath: previousPath,
      )) {
        final previousFile = File(previousPath);
        if (await previousFile.exists()) await previousFile.delete();
      }
    }
    return target.path;
  }

  Future<bool> isSafeInstalledManifestPath({
    required String extensionId,
    required String manifestPath,
  }) async {
    final root = await getApplicationSupportDirectory();
    return ExtensionInstallPathPolicy.isSafeManifestPathOnDisk(
      extensionsRoot: path.join(root.path, 'extensions'),
      extensionId: extensionId,
      manifestPath: manifestPath,
    );
  }

  Future<void> uninstallExtension(String extensionId) async {
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{2,127}$').hasMatch(extensionId)) {
      throw ArgumentError.value(extensionId, 'extensionId', 'Invalid extension identifier.');
    }
    final rows = await database.loadInstalledExtensions();
    Map<String, Object?>? row;
    for (final item in rows) {
      if (item['extension_id'] == extensionId) {
        row = item;
        break;
      }
    }

    // Remove the authoritative record first. A filesystem cleanup failure can
    // leave an orphan to be collected later, but must never leave an installed
    // extension record pointing at a deleted manifest.
    await database.removeInstalledExtension(extensionId);
    if (row == null || row['install_path'] is! String) return;

    final manifestPath = row['install_path'] as String;
    if (!await isSafeInstalledManifestPath(
      extensionId: extensionId,
      manifestPath: manifestPath,
    )) {
      // The DB record is gone, but a corrupted path is deliberately not
      // followed. Never delete arbitrary files from a path stored in SQLite.
      return;
    }

    final file = File(manifestPath);
    if (await file.exists()) await file.delete();
    final versionDirectory = file.parent;
    if (await versionDirectory.exists() && await versionDirectory.list().isEmpty) {
      await versionDirectory.delete();
    }
    final idDirectory = versionDirectory.parent;
    if (await idDirectory.exists() && await idDirectory.list().isEmpty) {
      await idDirectory.delete();
    }
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
        response.detachSocket().then((socket) => socket.destroy());
        throw HttpException('Repository redirects are not followed; add the final HTTPS URL instead.', uri: uri);
      }
      if (response.statusCode != HttpStatus.ok) {
        response.detachSocket().then((socket) => socket.destroy());
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
    if (addresses.isEmpty || addresses.any(isNonPublicAddress)) {
      throw const HttpException('Repository hostname resolved to a non-public address.');
    }
  }

  static bool isNonPublicAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      return _isNonPublicIpv4(bytes);
    }
    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
      final allZero = bytes.every((byte) => byte == 0);
      final loopback = bytes.take(15).every((byte) => byte == 0) && bytes[15] == 1;
      final uniqueLocal = (bytes[0] & 0xfe) == 0xfc;
      final linkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80;
      final multicast = bytes[0] == 0xff;
      final ipv4Mapped = bytes.take(10).every((byte) => byte == 0) &&
          bytes[10] == 0xff &&
          bytes[11] == 0xff;
      if (ipv4Mapped) return _isNonPublicIpv4(bytes.sublist(12, 16));

      // Keep network-level checks aligned with RepositoryPolicy's literal gate.
      // Only global-unicast 2000::/3 is accepted; several transition and
      // special-purpose prefixes are denied even though they fall inside it.
      final globalUnicast = (bytes[0] & 0xe0) == 0x20;
      final documentation = bytes[0] == 0x20 &&
          bytes[1] == 0x01 &&
          bytes[2] == 0x0d &&
          bytes[3] == 0xb8;
      final teredo = bytes[0] == 0x20 &&
          bytes[1] == 0x01 &&
          bytes[2] == 0x00 &&
          bytes[3] == 0x00;
      final sixToFour = bytes[0] == 0x20 && bytes[1] == 0x02;
      final orchid = bytes[0] == 0x20 &&
          bytes[1] == 0x01 &&
          bytes[2] == 0x00 &&
          ((bytes[3] & 0xf0) == 0x10 || (bytes[3] & 0xf0) == 0x20);

      return allZero ||
          loopback ||
          uniqueLocal ||
          linkLocal ||
          multicast ||
          !globalUnicast ||
          documentation ||
          teredo ||
          sixToFour ||
          orchid;
    }
    return true;
  }

  static bool _isNonPublicIpv4(List<int> bytes) {
    if (bytes.length != 4) return true;
    final a = bytes[0], b = bytes[1], c = bytes[2];
    return a == 0 ||
        a == 10 ||
        a == 127 ||
        a >= 224 ||
        (a == 100 && b >= 64 && b <= 127) ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && (b == 168 || (b == 0 && c == 0) || (b == 0 && c == 2))) ||
        (a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100))) ||
        (a == 203 && b == 0 && c == 113);
  }

  String _sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

  void dispose() => _client.close(force: true);
}
