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
class DeclarativeJsonProvider implements SourceProvider, SeriesProvider, ChapterFeedProvider, ReaderPagesProvider, CreatorWorksProvider {
  DeclarativeJsonProvider({
    required this.manifest,
    required this.fetcher,
  }) {
    final validation = const ExtensionManifestPolicy().validate(manifest);
    if (!validation.accepted) throw ArgumentError(validation.issues.join('; '));
  }

  final DeclarativeExtensionManifest manifest;
  final DeclarativeJsonFetcher fetcher;

  @override
  late final ProviderDescriptor descriptor = ProviderDescriptor(
        id: manifest.id,
        name: manifest.name,
        homepage: manifest.homepage,
        capabilities: {
          if (manifest.capabilities.contains(ExtensionCapability.search)) ProviderCapability.search,
          if (manifest.capabilities.contains(ExtensionCapability.seriesDetails)) ProviderCapability.series,
          if (manifest.capabilities.contains(ExtensionCapability.chapterFeed)) ProviderCapability.chapters,
          if (manifest.capabilities.contains(ExtensionCapability.readerPages)) ProviderCapability.pages,
          if (manifest.capabilities.contains(ExtensionCapability.creatorWorks)) ProviderCapability.creators,
        },
        isBuiltIn: false,
        enabledByDefault: manifest.enabledByDefault,
      );

  @override
  Future<ProviderResponse<List<WorkCandidate>>> search(
    String query, {
    required CancellationToken cancellationToken,
  }) async {
    if (cancellationToken.isCancelled) {
      return ProviderResponse(status: ProviderResultStatus.cancelled, message: cancellationToken.reason);
    }
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


  @override
  Future<ProviderResponse<WorkCandidate>> getSeries(
    String seriesId, {
    required CancellationToken cancellationToken,
  }) async {
    final endpoint = _findEndpoint(ExtensionCapability.seriesDetails);
    if (endpoint == null) {
      return const ProviderResponse(status: ProviderResultStatus.unsupported, message: 'Series details are unsupported.');
    }
    try {
      cancellationToken.throwIfCancelled();
      final uri = endpoint.buildUri(manifest.baseUri, seriesId: seriesId);
      _validateRequestUri(uri);
      final payload = await fetcher.getJson(
        uri,
        cancellationToken: cancellationToken,
        maxResponseBytes: endpoint.maxResponseBytes,
      );
      cancellationToken.throwIfCancelled();
      final value = endpoint.resultPath.read(payload);
      if (value is! Map) {
        return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Series response did not match its declared path.');
      }
      final fields = const DeclarativeJsonExtractor().fields(endpoint, Map<String, Object?>.from(value));
      final candidate = _candidateFromFields(fields);
      if (candidate == null) {
        return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Series response is missing required mapped fields.');
      }
      return ProviderResponse(status: ProviderResultStatus.success, data: candidate);
    } on Object catch (error) {
      return _error<WorkCandidate>(error);
    }
  }

  @override
  Future<ProviderResponse<List<ChapterUnit>>> getChapters(
    String seriesId, {
    required CancellationToken cancellationToken,
    List<String> translatedLanguages = const ['en'],
    int limit = 100,
    int offset = 0,
  }) async {
    final endpoint = _findEndpoint(ExtensionCapability.chapterFeed);
    if (endpoint == null) {
      return const ProviderResponse(status: ProviderResultStatus.unsupported, message: 'Chapter feeds are unsupported.');
    }
    if (limit < 1 || limit > 500 || offset < 0) {
      return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Invalid chapter pagination.');
    }
    try {
      cancellationToken.throwIfCancelled();
      final uri = endpoint.buildUri(
        manifest.baseUri,
        seriesId: seriesId,
        page: offset ~/ limit + 1,
        limit: limit,
        language: translatedLanguages.join(','),
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
      final chapters = <ChapterUnit>[];
      for (final record in records) {
        final fields = extractor.fields(endpoint, record);
        final id = fields['id'];
        final rawUrl = fields['url'];
        if (id is! String || id.trim().isEmpty || rawUrl is! String) continue;
        final url = Uri.tryParse(rawUrl);
        if (url == null || !_isAllowedWebUri(url)) continue;
        final kindValue = fields['kind'];
        final kindMatches = ChapterKind.values.where((item) => item.name == kindValue);
        final kind = kindMatches.isEmpty ? ChapterKind.regular : kindMatches.first;
        final miniGroup = fields['miniGroupId'] is String ? fields['miniGroupId'] as String : null;
        if (kind == ChapterKind.miniChapter && (miniGroup == null || miniGroup.trim().isEmpty)) continue;
        final numberValue = fields['chapterNumber'];
        final volumeValue = fields['volumeNumber'];
        final miniIndexValue = fields['miniIndex'];
        final miniCountValue = fields['miniCount'];
        final language = fields['languageCode'] is String ? fields['languageCode'] as String : null;
        final publishedValue = fields['publishedAt'];
        final publishedAt = publishedValue is String ? DateTime.tryParse(publishedValue) : null;
        chapters.add(ChapterUnit(
          id: manifest.id + ':' + seriesId + ':' + id,
          editionId: manifest.id + ':' + seriesId + ':' + (language ?? 'und'),
          kind: kind,
          title: fields['title'] is String ? fields['title'] as String : null,
          chapterNumber: numberValue is num ? numberValue.toDouble() : null,
          volumeNumber: volumeValue is int ? volumeValue : null,
          miniGroupId: miniGroup,
          miniIndex: miniIndexValue is int ? miniIndexValue : null,
          miniCount: miniCountValue is int ? miniCountValue : null,
          listings: [
            ChapterListing(
              providerId: manifest.id,
              externalId: id,
              url: url,
              languageCode: language,
              releaseGroup: fields['releaseGroup'] is String ? fields['releaseGroup'] as String : null,
              publishedAt: publishedAt,
              isOfficialTranslation: fields['isOfficialTranslation'] == true,
            ),
          ],
        ));
      }
      return ProviderResponse(status: ProviderResultStatus.success, data: List.unmodifiable(chapters));
    } on Object catch (error) {
      return _error<List<ChapterUnit>>(error);
    }
  }

  @override
  Future<ProviderResponse<List<WorkCandidate>>> getCreatorWorks(
    String creatorId, {
    required CancellationToken cancellationToken,
    int limit = 100,
    int offset = 0,
  }) async {
    final endpoint = _findEndpoint(ExtensionCapability.creatorWorks);
    if (endpoint == null) {
      return const ProviderResponse(status: ProviderResultStatus.unsupported, message: 'Creator works are unsupported.');
    }
    if (creatorId.trim().isEmpty || limit < 1 || limit > 500 || offset < 0) {
      return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Invalid creator pagination.');
    }
    try {
      cancellationToken.throwIfCancelled();
      final uri = endpoint.buildUri(
        manifest.baseUri,
        creatorId: creatorId,
        page: offset ~/ limit + 1,
        limit: limit,
      );
      _validateRequestUri(uri);
      final payload = await fetcher.getJson(
        uri,
        cancellationToken: cancellationToken,
        maxResponseBytes: endpoint.maxResponseBytes,
      );
      cancellationToken.throwIfCancelled();
      final extractor = const DeclarativeJsonExtractor();
      final candidates = <WorkCandidate>[];
      for (final record in extractor.records(endpoint, payload)) {
        final candidate = _candidateFromFields(extractor.fields(endpoint, record));
        if (candidate != null) candidates.add(candidate);
      }
      return ProviderResponse(status: ProviderResultStatus.success, data: List.unmodifiable(candidates));
    } on Object catch (error) {
      return _error<List<WorkCandidate>>(error);
    }
  }

  @override
  Future<ProviderResponse<ReaderPageManifest>> getPages(
    String chapterId, {
    required CancellationToken cancellationToken,
    bool dataSaver = false,
  }) async {
    final endpoint = _findEndpoint(ExtensionCapability.readerPages);
    if (endpoint == null) {
      return const ProviderResponse(status: ProviderResultStatus.unsupported, message: 'Reader pages are unsupported.');
    }
    try {
      cancellationToken.throwIfCancelled();
      final uri = endpoint.buildUri(manifest.baseUri, chapterId: chapterId);
      _validateRequestUri(uri);
      final payload = await fetcher.getJson(
        uri,
        cancellationToken: cancellationToken,
        maxResponseBytes: endpoint.maxResponseBytes,
      );
      cancellationToken.throwIfCancelled();
      final value = endpoint.resultPath.read(payload);
      if (value is! Map) {
        return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Page manifest did not match its declared path.');
      }
      final fields = const DeclarativeJsonExtractor().fields(endpoint, Map<String, Object?>.from(value));
      final baseValue = fields['baseUrl'];
      final hash = fields['hash'];
      final filenames = _strings(fields['filenames']);
      final saverFilenames = _strings(fields['dataSaverFilenames']);
      final baseUrl = baseValue is String ? Uri.tryParse(baseValue) : null;
      if (baseUrl == null || !_isAllowedWebUri(baseUrl) || hash is! String || filenames.isEmpty) {
        return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Page manifest contains invalid URLs or filenames.');
      }
      final pageManifest = ReaderPageManifest(
        chapterId: chapterId,
        baseUrl: baseUrl,
        hash: hash,
        normalFilenames: filenames,
        dataSaverFilenames: saverFilenames,
      );
      return ProviderResponse(status: ProviderResultStatus.success, data: pageManifest);
    } on Object catch (error) {
      return _error<ReaderPageManifest>(error);
    }
  }

  WorkCandidate? _candidateFromFields(Map<String, Object?> fields) {
    final id = fields['id'];
    final title = fields['title'];
    final rawUrl = fields['url'];
    if (id is! String || id.trim().isEmpty || title is! String || title.trim().isEmpty ||
        rawUrl is! String) return null;
    final providerUrl = Uri.tryParse(rawUrl);
    if (providerUrl == null || !_isAllowedWebUri(providerUrl)) return null;
    final coverValue = fields['coverUrl'];
    final cover = coverValue is String ? Uri.tryParse(coverValue) : null;
    final yearValue = fields['year'];
    final formatValue = fields['format'];
    final formats = WorkFormat.values.where((item) => item.name == formatValue);
    return WorkCandidate(
      providerId: manifest.id,
      externalId: id,
      title: title,
      providerUrl: providerUrl,
      alternateTitles: _strings(fields['alternateTitles']),
      creatorNames: _strings(fields['creatorNames']),
      year: yearValue is int ? yearValue : null,
      format: formats.isEmpty ? WorkFormat.unknown : formats.first,
      language: fields['language'] is String ? fields['language'] as String : null,
      description: fields['description'] is String ? fields['description'] as String : null,
      coverUrl: cover != null && _isAllowedWebUri(cover) ? cover : null,
      tags: _strings(fields['tags']),
    );
  }

  ProviderResponse<T> _error<T>(Object error) {
    if (error is OperationCancelled) {
      return ProviderResponse(status: ProviderResultStatus.cancelled, message: error.reason);
    }
    if (error is TimeoutException) {
      return const ProviderResponse(status: ProviderResultStatus.timedOut, message: 'Source request timed out.');
    }
    if (error is DeclarativeFetchException) {
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
      return ProviderResponse(status: ProviderResultStatus.failed, message: 'Source returned HTTP ' + error.statusCode.toString() + '.');
    }
    if (error is FormatException) {
      return ProviderResponse(status: ProviderResultStatus.failed, message: error.message);
    }
    return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Source request failed.');
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
