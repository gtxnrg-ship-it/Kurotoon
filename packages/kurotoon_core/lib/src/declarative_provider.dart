import 'dart:async';

import 'cancellation.dart';
import 'catalog_entities.dart';
import 'extension_manifest.dart';
import 'models.dart';
import 'provider_runtime.dart';

class DeclarativeFetchException implements Exception {
  const DeclarativeFetchException(this.statusCode, {this.retryAfter});

  final int statusCode;
  final Duration? retryAfter;
}

abstract interface class DeclarativeJsonFetcher {
  Future<Object?> getJson(
    Uri uri, {
    required CancellationToken cancellationToken,
    required int maxResponseBytes,
  });
}

/// A restricted source adapter: it can only issue declared JSON GET requests,
/// extract mapped fields, and return normalized catalog candidates.
class DeclarativeJsonProvider implements SourceProvider {
  DeclarativeJsonProvider({
    required this.manifest,
    required this.fetcher,
  }) {
    final validation = const ExtensionManifestPolicy().validate(manifest);
    if (!validation.accepted) throw ArgumentError(validation.issues.join('; '));
    descriptor = ProviderDescriptor(
      id: manifest.id,
      name: manifest.name,
      homepage: manifest.homepage,
      capabilities: {
        if (manifest.capabilities.contains(ExtensionCapability.search)) ProviderCapability.search,
      },
      isBuiltIn: false,
      enabledByDefault: manifest.enabledByDefault,
    );
  }

  final DeclarativeExtensionManifest manifest;
  final DeclarativeJsonFetcher fetcher;
  late final ProviderDescriptor descriptor;

  @override
  ProviderDescriptor get descriptor => _descriptor;
  late final ProviderDescriptor _descriptor = _buildDescriptor();

  ProviderDescriptor _buildDescriptor() => ProviderDescriptor(
        id: manifest.id,
        name: manifest.name,
        homepage: manifest.homepage,
        capabilities: {
          if (manifest.capabilities.contains(ExtensionCapability.search)) ProviderCapability.search,
        },
        isBuiltIn: false,
        enabledByDefault: manifest.enabledByDefault,
      );

  @override
  Future<ProviderResponse<List<WorkCandidate>>> search(
    String query, {
    required CancellationToken cancellationToken,
  }) async {
    cancellationToken.throwIfCancelled();
    final endpoint = _findEndpoint(ExtensionCapability.search);
    if (endpoint == null) {
      return const ProviderResponse(
        status: ProviderResultStatus.unsupported,
        message: 'This extension does not provide search.',
      );
    }
    if (query.trim().isEmpty) {
      return const ProviderResponse(status: ProviderResultStatus.success, data: []);
    }
    try {
      final uri = endpoint.buildUri(
        manifest.baseUri,
        queryText: query.trim(),
        page: 1,
        limit: 25,
      );
      _validateRequestUri(uri);
      final payload = await fetcher.getJson(
        uri,
        cancellationToken: cancellationToken,
        maxResponseBytes: endpoint.maxResponseBytes,
      );
      cancellationToken.throwIfCancelled();
      final extractor = const DeclarativeJsonExtractor();
      final records = extractor.records(endpoint, payload);
      final candidates = <WorkCandidate>[];
      for (final record in records) {
        final fields = extractor.fields(endpoint, record);
        final id = fields['id'];
        final title = fields['title'];
        final rawUrl = fields['url'];
        if (id is! String || id.trim().isEmpty || title is! String || title.trim().isEmpty ||
            rawUrl is! String) continue;
        final providerUrl = Uri.tryParse(rawUrl);
        if (providerUrl == null || !_isAllowedWebUri(providerUrl)) continue;
        final coverValue = fields['coverUrl'];
        final cover = coverValue is String ? Uri.tryParse(coverValue) : null;
        final yearValue = fields['year'];
        final formatValue = fields['format'];
        final format = WorkFormat.values.where((item) => item.name == formatValue);
        candidates.add(WorkCandidate(
          providerId: manifest.id,
          externalId: id,
          title: title,
          providerUrl: providerUrl,
          alternateTitles: _strings(fields['alternateTitles']),
          creatorNames: _strings(fields['creatorNames']),
          year: yearValue is int ? yearValue : null,
          format: format.isEmpty ? WorkFormat.unknown : format.first,
          language: fields['language'] is String ? fields['language'] as String : null,
          description: fields['description'] is String ? fields['description'] as String : null,
          coverUrl: cover != null && _isAllowedWebUri(cover) ? cover : null,
          tags: _strings(fields['tags']),
        ));
      }
      return ProviderResponse(
        status: ProviderResultStatus.success,
        data: List.unmodifiable(candidates),
      );
    } on OperationCancelled catch (error) {
      return ProviderResponse(status: ProviderResultStatus.cancelled, message: error.reason);
    } on TimeoutException {
      return const ProviderResponse(status: ProviderResultStatus.timedOut, message: 'Source request timed out.');
    } on DeclarativeFetchException catch (error) {
      if (error.statusCode == 429) {
        return ProviderResponse(
          status: ProviderResultStatus.rateLimited,
          message: 'Source rate-limited this request.',
          retryAfter: error.retryAfter,
        );
      }
      if (error.statusCode == 401 || error.statusCode == 403 || error.statusCode == 451) {
        return const ProviderResponse(status: ProviderResultStatus.blocked, message: 'Source denied this request.');
      }
      return ProviderResponse(
        status: ProviderResultStatus.failed,
        message: 'Source returned HTTP ' + error.statusCode.toString() + '.',
      );
    } on FormatException catch (error) {
      return ProviderResponse(status: ProviderResultStatus.failed, message: error.message);
    } on Object {
      return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Source request failed.');
    }
  }

  JsonEndpointSpec? _findEndpoint(ExtensionCapability capability) {
    for (final endpoint in manifest.endpoints) {
      if (endpoint.capability == capability) return endpoint;
    }
    return null;
  }

  void _validateRequestUri(Uri uri) {
    if (!_isAllowedWebUri(uri)) {
      throw const FormatException('Endpoint URL is outside the extension allow-list.');
    }
  }

  bool _isAllowedWebUri(Uri uri) =>
      uri.isAbsolute &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      manifest.allowedHosts.contains(uri.host.toLowerCase());

  List<String> _strings(Object? value) {
    if (value is String && value.trim().isNotEmpty) return [value.trim()];
    if (value is! List) return const [];
    return List.unmodifiable(value.whereType<String>().map((item) => item.trim()).where((item) => item.isNotEmpty));
  }
}
