import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'extension_manifest.dart';
import 'repository_policy.dart';

enum RepositoryTrust { builtIn, userAdded, unverified }

class ExtensionRepository {
  const ExtensionRepository({
    required this.id,
    required this.name,
    required this.indexUri,
    this.description,
    this.website,
    this.iconUri,
    this.trust = RepositoryTrust.userAdded,
  });

  final String id;
  final String name;
  final Uri indexUri;
  final String? description;
  final Uri? website;
  final Uri? iconUri;
  final RepositoryTrust trust;
}

class ExtensionPackageEntry {
  const ExtensionPackageEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.manifestUri,
    required this.sha256,
    required this.sizeBytes,
    required this.minimumAppApi,
    required this.capabilities,
    this.description,
    this.website,
    this.iconUri,
    this.languageCodes = const [],
    this.contentRating = 'unknown',
  });

  final String id;
  final String name;
  final String version;
  final Uri manifestUri;
  final String sha256;
  final int sizeBytes;
  final int minimumAppApi;
  final Set<ExtensionCapability> capabilities;
  final String? description;
  final Uri? website;
  final Uri? iconUri;
  final List<String> languageCodes;
  final String contentRating;

  bool get hashIsValid => RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256);

  factory ExtensionPackageEntry.fromJson(
    Map<String, Object?> json, {
    required Uri indexUri,
  }) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Extension entry is missing ' + key + '.');
      }
      return value;
    }

    final id = requiredString('id');
    final name = requiredString('name');
    final version = requiredString('version');
    final manifestValue = requiredString('manifestUrl');
    final digest = requiredString('sha256').toLowerCase();
    final size = json['sizeBytes'];
    final api = json['minimumAppApi'];
    final capabilitiesJson = json['capabilities'];
    if (size is! int || size < 1 || size > 2 * 1024 * 1024 ||
        api is! int || api < 1 || capabilitiesJson is! List) {
      throw FormatException('Extension ' + id + ' has invalid size, API, or capabilities.');
    }
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{2,127}$').hasMatch(id)) {
      throw FormatException('Extension id is not a valid stable identifier: ' + id);
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw FormatException('Extension ' + id + ' has an invalid SHA-256 digest.');
    }
    final manifestUri = indexUri.resolve(manifestValue);
    _validateRepositoryResourceUri(manifestUri, indexUri);

    final capabilities = <ExtensionCapability>{};
    for (final value in capabilitiesJson) {
      if (value is! String) throw FormatException('Extension ' + id + ' has an invalid capability.');
      final matches = ExtensionCapability.values.where((capability) => capability.name == value);
      if (matches.isEmpty) throw FormatException('Unsupported extension capability: ' + value);
      capabilities.add(matches.single);
    }

    Uri? optionalUri(String key) {
      final value = json[key];
      if (value is! String) return null;
      final uri = indexUri.resolve(value);
      _validateRepositoryResourceUri(uri, indexUri);
      return uri;
    }

    final languages = json['languageCodes'];
    if (languages != null && (languages is! List || languages.any((item) => item is! String))) {
      throw FormatException('Extension ' + id + ' has invalid language codes.');
    }
    final rating = json['contentRating'] as String? ?? 'unknown';
    if (!{'safe', 'mixed', 'mature', 'unknown'}.contains(rating)) {
      throw FormatException('Extension ' + id + ' has an unsupported content rating.');
    }

    return ExtensionPackageEntry(
      id: id,
      name: name,
      version: version,
      manifestUri: manifestUri,
      sha256: digest,
      sizeBytes: size,
      minimumAppApi: api,
      capabilities: Set.unmodifiable(capabilities),
      description: json['description'] as String?,
      website: optionalUri('website'),
      iconUri: optionalUri('iconUrl'),
      languageCodes: List.unmodifiable((languages as List? ?? const []).cast<String>()),
      contentRating: rating,
    );
  }
}

void _validateRepositoryResourceUri(Uri resource, Uri indexUri) {
  if (!resource.isAbsolute || resource.scheme != 'https' || resource.host.isEmpty ||
      resource.userInfo.isNotEmpty || (resource.hasPort && resource.port != 443) ||
      resource.hasFragment) {
    throw const FormatException('Repository resources must use public HTTPS URLs.');
  }
  if (resource.host.toLowerCase() != indexUri.host.toLowerCase()) {
    throw const FormatException('Repository resources must use the repository index host.');
  }
}

class ExtensionRepositoryIndex {
  const ExtensionRepositoryIndex({
    required this.schemaVersion,
    required this.id,
    required this.name,
    required this.generatedAt,
    required this.extensions,
    this.description,
    this.website,
  });

  final int schemaVersion;
  final String id;
  final String name;
  final DateTime generatedAt;
  final String? description;
  final Uri? website;
  final List<ExtensionPackageEntry> extensions;

  factory ExtensionRepositoryIndex.fromJson(
    Map<String, Object?> json, {
    required Uri indexUri,
  }) {
    final schema = json['schemaVersion'];
    final id = json['id'];
    final name = json['name'];
    final generatedAt = DateTime.tryParse(json['generatedAt'] as String? ?? '');
    final extensionJson = json['extensions'];
    if (schema is! int || id is! String || name is! String ||
        generatedAt == null || extensionJson is! List) {
      throw const FormatException('Repository index is missing required metadata.');
    }
    if (schema != 1) throw FormatException('Unsupported repository index schema: ' + schema.toString());

    final entries = <ExtensionPackageEntry>[];
    final ids = <String>{};
    for (final value in extensionJson) {
      if (value is! Map) throw const FormatException('Extension entry must be an object.');
      final entry = ExtensionPackageEntry.fromJson(
        Map<String, Object?>.from(value),
        indexUri: indexUri,
      );
      if (!ids.add(entry.id)) throw FormatException('Duplicate extension id: ' + entry.id);
      entries.add(entry);
    }
    final websiteValue = json['website'];
    return ExtensionRepositoryIndex(
      schemaVersion: schema,
      id: id,
      name: name,
      generatedAt: generatedAt,
      description: json['description'] as String?,
      website: websiteValue is String ? Uri.tryParse(websiteValue) : null,
      extensions: List.unmodifiable(entries),
    );
  }
}

class RepositoryIndexValidator {
  const RepositoryIndexValidator({
    this.maxIndexBytes = 2 * 1024 * 1024,
    this.maxExtensions = 5000,
    this.policy = const RepositoryPolicy(),
  });

  final int maxIndexBytes;
  final int maxExtensions;
  final RepositoryPolicy policy;

  ExtensionRepositoryIndex parse({
    required String body,
    required Uri indexUri,
  }) {
    final decision = policy.validate(indexUri.toString());
    if (!decision.allowed) throw FormatException(decision.reason);
    final bytes = utf8.encode(body);
    if (bytes.length > maxIndexBytes) {
      throw FormatException('Repository index exceeds the configured byte limit.');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('Repository index root must be an object.');
    final index = ExtensionRepositoryIndex.fromJson(
      Map<String, Object?>.from(decoded),
      indexUri: indexUri,
    );
    if (index.extensions.length > maxExtensions) {
      throw FormatException('Repository contains too many extensions.');
    }
    return index;
  }
}

class ExtensionPackageVerifier {
  const ExtensionPackageVerifier({this.maxPackageBytes = 2 * 1024 * 1024});

  final int maxPackageBytes;

  void verify({
    required List<int> bytes,
    required ExtensionPackageEntry entry,
  }) {
    if (bytes.length != entry.sizeBytes) {
      throw const FormatException('Downloaded extension size does not match repository metadata.');
    }
    if (bytes.length > maxPackageBytes) {
      throw const FormatException('Downloaded extension exceeds the package size limit.');
    }
    final actual = sha256.convert(bytes).toString();
    if (actual != entry.sha256.toLowerCase()) {
      throw const FormatException('Extension SHA-256 verification failed.');
    }
  }
}

class AddRepositoryLink {
  const AddRepositoryLink._();

  static const scheme = 'kurotoon';
  static const host = 'add-repo';

  static Uri create(Uri indexUri) => Uri(
        scheme: scheme,
        host: host,
        queryParameters: {'url': indexUri.toString()},
      );

  static Uri parse(Uri link) {
    if (link.scheme != scheme || link.host != host) {
      throw const FormatException('Not a KuroToon add-repository link.');
    }
    final raw = link.queryParameters['url'];
    if (raw == null || raw.isEmpty) {
      throw const FormatException('Add-repository link is missing its index URL.');
    }
    final decision = const RepositoryPolicy().validate(raw);
    if (!decision.allowed || decision.uri == null) throw FormatException(decision.reason);
    return decision.uri!;
  }
}
