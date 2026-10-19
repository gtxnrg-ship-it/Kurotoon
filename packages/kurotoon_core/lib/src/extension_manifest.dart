class JsonPath {
  JsonPath(List<Object> segments) : segments = List.unmodifiable(segments) {
    if (segments.any((segment) =>
        !(segment is String && segment.isNotEmpty) &&
        !(segment is int && segment >= 0))) {
      throw ArgumentError('JSON paths contain non-empty keys or non-negative list indexes.');
    }
  }

  final List<Object> segments;

  Object? read(Object? root) {
    Object? value = root;
    for (final segment in segments) {
      if (segment is String && value is Map) {
        value = value[segment];
      } else if (segment is int && value is List && segment < value.length) {
        value = value[segment];
      } else {
        return null;
      }
    }
    return value;
  }
}

enum ExtensionCapability { search, seriesDetails, chapterFeed, readerPages, creatorWorks }

class JsonEndpointSpec {
  JsonEndpointSpec({
    required this.id,
    required this.capability,
    required this.path,
    required this.resultPath,
    required Map<String, String> query,
    required Map<String, JsonPath> fields,
    this.maxResponseBytes = 1048576,
  }) : query = Map.unmodifiable(query), fields = Map.unmodifiable(fields) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    if (maxResponseBytes < 1 || maxResponseBytes > 2 * 1024 * 1024) {
      throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes', 'Must be 1 byte to 2 MiB');
    }
  }

  final String id;
  final ExtensionCapability capability;
  final String path;
  final JsonPath resultPath;
  final Map<String, String> query;
  final Map<String, JsonPath> fields;
  final int maxResponseBytes;

  static const Set<String> _allowedPlaceholders = {
    'query', 'page', 'limit', 'seriesId', 'chapterId', 'language',
  };

  List<String> validate() {
    final issues = <String>[];
    String decodedPath;
    try {
      decodedPath = Uri.decodeComponent(path);
    } on FormatException {
      return const ['Endpoint path contains malformed percent encoding.'];
    }
    if (!path.startsWith('/') || path.startsWith('//') || path.contains('://') ||
        path.contains('#') || decodedPath.split('/').any((part) => part == '..' || part == '.')) {
      issues.add('Endpoint path must be root-relative and contain no URL authority or traversal.');
    }
    for (final value in query.values) {
      for (final match in RegExp(r'\{([^}]+)\}').allMatches(value)) {
        if (!_allowedPlaceholders.contains(match.group(1))) {
          issues.add('Unsupported query placeholder: \${match.group(1)}');
        }
      }
      if (value.contains('{') != value.contains('}')) {
        issues.add('Malformed query placeholder in endpoint $id.');
      }
    }
    final requiredFields = switch (capability) {
      ExtensionCapability.search || ExtensionCapability.seriesDetails || ExtensionCapability.creatorWorks =>
        const {'id', 'title', 'url'},
      ExtensionCapability.chapterFeed => const {'id', 'url'},
      ExtensionCapability.readerPages => const {'baseUrl', 'hash', 'filenames'},
    };
    if (!fields.keys.toSet().containsAll(requiredFields)) {
      issues.add('Endpoint ' + id + ' is missing required field mappings: ' +
          requiredFields.difference(fields.keys.toSet()).join(', ') + '.');
    }
    return List.unmodifiable(issues);
  }

  Uri buildUri(
    Uri baseUri, {
    String? queryText,
    int page = 1,
    int limit = 20,
    String? seriesId,
    String? chapterId,
    String? language,
  }) {
    final values = <String, String>{
      'query': queryText ?? '',
      'page': '$page',
      'limit': '$limit',
      'seriesId': seriesId ?? '',
      'chapterId': chapterId ?? '',
      'language': language ?? '',
    };
    final parameters = <String, String>{};
    for (final entry in query.entries) {
      var value = entry.value;
      for (final placeholder in _allowedPlaceholders) {
        value = value.replaceAll('{$placeholder}', values[placeholder]!);
      }
      parameters[entry.key] = value;
    }

    final segments = <String>[
      ...baseUri.pathSegments.where((segment) => segment.isNotEmpty),
    ];
    for (var segment in path.split('/').where((part) => part.isNotEmpty)) {
      for (final placeholder in _allowedPlaceholders) {
        segment = segment.replaceAll('{$placeholder}', values[placeholder]!);
      }
      // Uri.pathSegments encodes each segment; a supplied slash stays inside one segment.
      segments.add(segment);
    }
    return Uri(
      scheme: baseUri.scheme,
      userInfo: baseUri.userInfo.isEmpty ? null : baseUri.userInfo,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      pathSegments: segments,
      queryParameters: parameters.isEmpty ? null : parameters,
    );
  }
}

class DeclarativeExtensionManifest {
  DeclarativeExtensionManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.minimumAppApi,
    required this.homepage,
    required this.baseUri,
    required this.licenseId,
    required this.developer,
    required Set<String> allowedHosts,
    required List<JsonEndpointSpec> endpoints,
    this.enabledByDefault = false,
  }) : allowedHosts = Set.unmodifiable(allowedHosts.map((host) => host.toLowerCase())),
       endpoints = List.unmodifiable(endpoints) {
    if (id.trim().isEmpty || name.trim().isEmpty || version.trim().isEmpty || developer.trim().isEmpty) {
      throw ArgumentError('Extension manifest requires id, name, version, and developer.');
    }
  }

  final String id;
  final String name;
  final String version;
  final int minimumAppApi;
  final Uri homepage;
  final Uri baseUri;
  final String licenseId;
  final String developer;
  final Set<String> allowedHosts;
  final List<JsonEndpointSpec> endpoints;
  final bool enabledByDefault;

  Set<ExtensionCapability> get capabilities =>
      Set.unmodifiable(endpoints.map((endpoint) => endpoint.capability));
}

class ManifestValidation {
  const ManifestValidation({required this.accepted, required this.issues});
  final bool accepted;
  final List<String> issues;
}

class ExtensionManifestPolicy {
  const ExtensionManifestPolicy({
    this.supportedAppApi = 1,
    this.maxEndpoints = 32,
    this.allowedLicenses = const {'MIT', 'Apache-2.0', 'BSD-3-Clause', 'GPL-3.0-only', 'MPL-2.0'},
  });

  final int supportedAppApi;
  final int maxEndpoints;
  final Set<String> allowedLicenses;

  ManifestValidation validate(DeclarativeExtensionManifest manifest) {
    final issues = <String>[];
    if (manifest.minimumAppApi > supportedAppApi) issues.add('Extension requires a newer app API.');
    if (!allowedLicenses.contains(manifest.licenseId)) issues.add('Extension license is not approved.');
    if (manifest.endpoints.isEmpty || manifest.endpoints.length > maxEndpoints) {
      issues.add('Endpoint count is outside the supported range.');
    }
    _validatePublicHttps(manifest.homepage, 'Extension homepage', issues);
    _validatePublicHttps(manifest.baseUri, 'API base URL', issues);
    if (manifest.baseUri.hasQuery || manifest.baseUri.hasFragment) {
      issues.add('API base URL cannot contain a query or fragment.');
    }

    final baseHost = manifest.baseUri.host.toLowerCase();
    if (!manifest.allowedHosts.contains(baseHost)) issues.add('Allowed-host list must include the API base host.');
    for (final value in manifest.allowedHosts) {
      final host = value.trim().toLowerCase();
      if (host.isEmpty || host.contains('*') || host.contains('/') || host.contains(':') ||
          host.startsWith('.') || host.endsWith('.')) {
        issues.add('Allowed hosts must be exact hostnames; wildcards and ports are forbidden.');
        continue;
      }
      if (_isLocalHost(host) || _isPrivateIp(host)) issues.add('Local/private-network hosts are forbidden.');
    }
    final ids = <String>{};
    for (final endpoint in manifest.endpoints) {
      if (!ids.add(endpoint.id)) issues.add('Duplicate endpoint id: \${endpoint.id}');
      issues.addAll(endpoint.validate().map((issue) => '\${endpoint.id}: $issue'));
    }
    return ManifestValidation(accepted: issues.isEmpty, issues: List.unmodifiable(issues));
  }

  void _validatePublicHttps(Uri uri, String label, List<String> issues) {
    if (!uri.isAbsolute || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || (uri.hasPort && uri.port != 443) || uri.hasFragment) {
      issues.add('$label must be public HTTPS without credentials, custom ports, or fragments.');
      return;
    }
    final host = uri.host.toLowerCase();
    if (_isLocalHost(host) || _isPrivateIp(host)) issues.add('$label cannot point to a local/private host.');
  }

  bool _isLocalHost(String host) =>
      host == 'localhost' || host.endsWith('.localhost') || host.endsWith('.local');

  bool _isPrivateIp(String host) {
    if (host == '::' || host == '::1' || host.startsWith('fc') ||
        host.startsWith('fd') || host.startsWith('fe80:')) return true;
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((n) => n == null || n < 0 || n > 255)) return false;
    final a = octets[0]!;
    final b = octets[1]!;
    return a == 0 || a == 10 || a == 127 || (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || a >= 224;
  }
}

/// Parses only declared JSON paths. It never evaluates source-provided code.
/// The transport must enforce redirect, DNS, host, and response-size policy.
class DeclarativeJsonExtractor {
  const DeclarativeJsonExtractor();

  List<Map<String, Object?>> records(JsonEndpointSpec endpoint, Object? payload) {
    final value = endpoint.resultPath.read(payload);
    if (value is! List) return const [];
    return List.unmodifiable(value.whereType<Map>().map(
      (record) => Map<String, Object?>.from(record),
    ));
  }

  Map<String, Object?> fields(JsonEndpointSpec endpoint, Map<String, Object?> record) {
    final result = <String, Object?>{};
    for (final entry in endpoint.fields.entries) {
      result[entry.key] = entry.value.read(record);
    }
    return Map.unmodifiable(result);
  }
}



/// Parses a declarative extension manifest. No downloaded source code is executed.
DeclarativeExtensionManifest parseDeclarativeExtensionManifest(Map<String, Object?> json) {
  String requiredString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Extension manifest is missing ' + key + '.');
    }
    return value;
  }

  List<Object> pathSegments(Object? value, String label) {
    if (value is! List || value.isEmpty ||
        value.any((item) => !(item is String && item.isNotEmpty) && !(item is int && item >= 0))) {
      throw FormatException(label + ' must be a non-empty JSON path.');
    }
    return List<Object>.from(value);
  }

  final id = requiredString(json, 'id');
  final name = requiredString(json, 'name');
  final version = requiredString(json, 'version');
  final homepage = Uri.tryParse(requiredString(json, 'homepage'));
  final baseUri = Uri.tryParse(requiredString(json, 'baseUrl'));
  final license = requiredString(json, 'license');
  final developer = requiredString(json, 'developer');
  final api = json['minimumAppApi'];
  final hostsJson = json['allowedHosts'];
  final endpointsJson = json['endpoints'];
  if (homepage == null || baseUri == null || api is! int ||
      hostsJson is! List || hostsJson.any((item) => item is! String) ||
      endpointsJson is! List) {
    throw const FormatException('Extension manifest contains invalid metadata.');
  }
  final endpoints = <JsonEndpointSpec>[];
  for (final value in endpointsJson) {
    if (value is! Map) throw const FormatException('Endpoint definition must be an object.');
    final endpoint = Map<String, Object?>.from(value);
    final capabilityName = requiredString(endpoint, 'capability');
    final capabilities = ExtensionCapability.values.where((item) => item.name == capabilityName);
    if (capabilities.isEmpty) throw FormatException('Unsupported capability: ' + capabilityName);
    final queryJson = endpoint['query'] ?? const <String, Object?>{};
    final fieldsJson = endpoint['fields'];
    if (queryJson is! Map || fieldsJson is! Map) {
      throw const FormatException('Endpoint query and field mappings must be objects.');
    }
    final query = <String, String>{};
    for (final entry in queryJson.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('Endpoint query values must be strings.');
      }
      query[entry.key as String] = entry.value as String;
    }
    final fields = <String, JsonPath>{};
    for (final entry in fieldsJson.entries) {
      if (entry.key is! String) throw const FormatException('Field mapping keys must be strings.');
      fields[entry.key as String] = JsonPath(pathSegments(entry.value, 'Field mapping'));
    }
    final responseBytes = endpoint['maxResponseBytes'] ?? 1048576;
    if (responseBytes is! int) throw const FormatException('Endpoint response limit must be an integer.');
    endpoints.add(JsonEndpointSpec(
      id: requiredString(endpoint, 'id'),
      capability: capabilities.single,
      path: requiredString(endpoint, 'path'),
      query: query,
      resultPath: JsonPath(pathSegments(endpoint['resultPath'], 'Result path')),
      fields: fields,
      maxResponseBytes: responseBytes,
    ));
  }

  final enabledByDefault = json['enabledByDefault'] ?? false;
  if (enabledByDefault is! bool) throw const FormatException('enabledByDefault must be boolean.');
  final manifest = DeclarativeExtensionManifest(
    id: id,
    name: name,
    version: version,
    minimumAppApi: api,
    homepage: homepage,
    baseUri: baseUri,
    licenseId: license,
    developer: developer,
    allowedHosts: Set<String>.from(hostsJson.cast<String>()),
    endpoints: endpoints,
    enabledByDefault: enabledByDefault,
  );
  final validation = const ExtensionManifestPolicy().validate(manifest);
  if (!validation.accepted) throw FormatException(validation.issues.join('; '));
  return manifest;
}
