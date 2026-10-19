import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cancellation.dart';
import 'catalog_entities.dart';
import 'models.dart';
import 'provider_runtime.dart';

class JsonHttpResponse {
  const JsonHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, List<String>> headers;
  final Map<String, Object?> body;

  String? header(String name) {
    final target = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == target && entry.value.isNotEmpty) return entry.value.first;
    }
    return null;
  }
}

abstract interface class JsonGetTransport {
  Future<JsonHttpResponse> get(Uri uri, {required CancellationToken cancellationToken});
}

/// Native Dart HTTP transport with a hard response cap and cooperative abort.
/// Only the fixed MangaDex API host is accepted; repository URLs never enter it.
class IoJsonGetTransport implements JsonGetTransport {
  IoJsonGetTransport({
    HttpClient? client,
    this.requestTimeout = const Duration(seconds: 7),
    this.maxResponseBytes = 2 * 1024 * 1024,
  }) : _client = client ?? HttpClient();

  final HttpClient _client;
  final Duration requestTimeout;
  final int maxResponseBytes;

  @override
  Future<JsonHttpResponse> get(
    Uri uri, {
    required CancellationToken cancellationToken,
  }) async {
    cancellationToken.throwIfCancelled();
    if (uri.scheme != 'https' || uri.host.toLowerCase() != 'api.mangadex.org') {
      throw ArgumentError('Only the HTTPS MangaDex API host is permitted');
    }
    if (requestTimeout <= Duration.zero || maxResponseBytes < 1) {
      throw ArgumentError('Invalid HTTP transport limits');
    }

    HttpClientRequest? request;
    void Function()? detach;
    try {
      request = await _client.getUrl(uri).timeout(requestTimeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Kurotoon/0.1');
      detach = cancellationToken.onCancel((_) => request?.abort());
      cancellationToken.throwIfCancelled();

      final response = await request.close().timeout(requestTimeout);
      final bytes = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in response) {
        cancellationToken.throwIfCancelled();
        received += chunk.length;
        if (received > maxResponseBytes) {
          request.abort();
          throw const FormatException('API response exceeded the size limit');
        }
        bytes.add(chunk);
      }

      final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('API response was not a JSON object');
      }
      final responseHeaders = <String, List<String>>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = List<String>.unmodifiable(values);
      });
      return JsonHttpResponse(
        statusCode: response.statusCode,
        headers: Map<String, List<String>>.unmodifiable(responseHeaders),
        body: Map<String, Object?>.from(decoded),
      );
    } on TimeoutException {
      request?.abort();
      rethrow;
    } on Object {
      if (cancellationToken.isCancelled) {
        throw OperationCancelled(cancellationToken.reason);
      }
      rethrow;
    } finally {
      detach?.call();
    }
  }

  void close({bool force = false}) => _client.close(force: force);
}

class MangaDexProvider implements SourceProvider {
  MangaDexProvider({
    JsonGetTransport? transport,
    Iterable<String> contentRatings = const ['safe', 'suggestive'],
    this.resultLimit = 25,
  })  : transport = transport ?? IoJsonGetTransport(),
        contentRatings = List.unmodifiable(contentRatings) {
    if (resultLimit < 1 || resultLimit > 100) {
      throw ArgumentError.value(resultLimit, 'resultLimit', 'Must be between 1 and 100');
    }
    if (this.contentRatings.isEmpty ||
        this.contentRatings.any((rating) => !_allowedRatings.contains(rating))) {
      throw ArgumentError.value(contentRatings, 'contentRatings', 'Contains an unsupported rating');
    }
  }

  static const Set<String> _allowedRatings = {
    'safe',
    'suggestive',
    'erotica',
    'pornographic',
  };

  final JsonGetTransport transport;
  final List<String> contentRatings;
  final int resultLimit;

  void close({bool force = false}) {
    if (transport is IoJsonGetTransport) {
      (transport as IoJsonGetTransport).close(force: force);
    }
  }

  @override
  final ProviderDescriptor descriptor = ProviderDescriptor(
    id: 'mangadex',
    name: 'MangaDex',
    homepage: Uri(scheme: 'https', host: 'mangadex.org'),
    capabilities: {ProviderCapability.search},
    isBuiltIn: true,
    enabledByDefault: true,
  );

  @override
  Future<ProviderResponse<List<WorkCandidate>>> search(
    String query, {
    required CancellationToken cancellationToken,
  }) async {
    final title = query.trim();
    if (title.isEmpty) {
      return const ProviderResponse(status: ProviderResultStatus.success, data: []);
    }
    if (title.length > 200) {
      return const ProviderResponse(
        status: ProviderResultStatus.failed,
        message: 'Search query is too long',
      );
    }
    try {
      cancellationToken.throwIfCancelled();
      String queryParam(String key, String value) =>
          '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}';
      final queryParts = <String>[
        queryParam('title', title),
        queryParam('limit', '$resultLimit'),
        for (final include in ['cover_art', 'author', 'artist']) queryParam('includes[]', include),
        for (final rating in contentRatings) queryParam('contentRating[]', rating),
        queryParam('order[relevance]', 'desc'),
      ];
      final uri = Uri.parse('https://api.mangadex.org/manga?${queryParts.join('&')}');
      final response = await transport.get(uri, cancellationToken: cancellationToken);
      cancellationToken.throwIfCancelled();

      if (response.statusCode == 429) {
        final seconds = int.tryParse(response.header('retry-after') ?? '');
        return ProviderResponse(
          status: ProviderResultStatus.rateLimited,
          message: 'MangaDex rate limit reached',
          retryAfter: seconds == null || seconds < 0 ? null : Duration(seconds: seconds),
        );
      }
      if (response.statusCode == 403 || response.statusCode == 451) {
        return const ProviderResponse(
          status: ProviderResultStatus.blocked,
          message: 'MangaDex did not permit this request',
        );
      }
      if (response.statusCode != 200) {
        return ProviderResponse(
          status: ProviderResultStatus.failed,
          message: 'MangaDex returned HTTP ${response.statusCode}',
        );
      }

      final rawData = response.body['data'];
      if (rawData is! List) {
        return const ProviderResponse(
          status: ProviderResultStatus.failed,
          message: 'MangaDex response did not contain a data list',
        );
      }
      final included = _objects(response.body['included']);
      final includedById = <String, Map<String, dynamic>>{
        for (final item in included)
          if (item['id'] is String) item['id'] as String: item,
      };

      final candidates = <WorkCandidate>[];
      var dropped = false;
      for (final item in rawData) {
        final manga = _map(item);
        if (manga == null || manga['id'] is! String) {
          dropped = true;
          continue;
        }
        final attributes = _map(manga['attributes']);
        if (attributes == null) {
          dropped = true;
          continue;
        }
        final titles = _titleValues(attributes['title']);
        if (titles.isEmpty) {
          dropped = true;
          continue;
        }
        final mangaId = manga['id'] as String;
        final alternateTitles = <String>[];
        for (final alt in _objects(attributes['altTitles'])) {
          alternateTitles.addAll(_titleValues(alt));
        }

        final creators = <String>{};
        for (final relationship in _objects(manga['relationships'])) {
          final type = relationship['type'];
          final id = relationship['id'];
          if ((type == 'author' || type == 'artist') && id is String) {
            final entity = includedById[id];
            final entityAttributes = _map(entity?['attributes']);
            final name = entityAttributes?['name'];
            if (name is String && name.trim().isNotEmpty) creators.add(name.trim());
          }
        }

        final coverFile = _coverFilename(manga, includedById);
        final coverUrl = coverFile == null
            ? null
            : Uri.https('uploads.mangadex.org', '/covers/$mangaId/$coverFile.256.jpg');
        final year = attributes['year'] is int
            ? attributes['year'] as int
            : int.tryParse('${attributes['year'] ?? ''}');
        final originalLanguage = attributes['originalLanguage'] as String?;
        final format = switch (originalLanguage) {
          'ko' => WorkFormat.manhwa,
          'zh' || 'zh-hk' => WorkFormat.manhua,
          'ja' => WorkFormat.manga,
          _ => WorkFormat.unknown,
        };

        candidates.add(WorkCandidate(
          providerId: descriptor.id,
          externalId: mangaId,
          title: titles.first,
          alternateTitles: alternateTitles,
          creatorNames: creators.toList(),
          year: year,
          format: format,
          language: originalLanguage,
          description: _localizedValue(attributes['description'], preferred: 'en'),
          coverUrl: coverUrl,
          tags: _objects(attributes['tags'])
              .map((tag) => _localizedValue(_map(tag['attributes'])?['name'], preferred: 'en'))
              .whereType<String>()
              .where((value) => value.trim().isNotEmpty)
              .toSet()
              .toList(),
          providerUrl: Uri.https('mangadex.org', '/title/$mangaId'),
        ));
      }

      return ProviderResponse(
        status: dropped ? ProviderResultStatus.partial : ProviderResultStatus.success,
        data: List.unmodifiable(candidates),
        message: dropped ? 'Some malformed MangaDex records were skipped' : null,
      );
    } on OperationCancelled catch (error) {
      return ProviderResponse(status: ProviderResultStatus.cancelled, message: error.reason);
    } on TimeoutException {
      return const ProviderResponse(
        status: ProviderResultStatus.timedOut,
        message: 'MangaDex request timed out',
      );
    } on FormatException {
      return const ProviderResponse(
        status: ProviderResultStatus.failed,
        message: 'MangaDex returned an invalid or oversized response',
      );
    } catch (error) {
      return ProviderResponse(
        status: ProviderResultStatus.failed,
        message: 'MangaDex request failed (${error.runtimeType})',
      );
    }
  }

  String? _coverFilename(
    Map<String, dynamic> manga,
    Map<String, Map<String, dynamic>> included,
  ) {
    for (final relationship in _objects(manga['relationships'])) {
      if (relationship['type'] != 'cover_art' || relationship['id'] is! String) continue;
      final cover = included[relationship['id'] as String];
      final attributes = _map(cover?['attributes']);
      final filename = attributes?['fileName'];
      if (filename is String && filename.trim().isNotEmpty) return filename;
    }
    return null;
  }

  static Map<String, dynamic>? _map(Object? value) =>
      value is Map<String, dynamic> ? value : null;

  static List<Map<String, dynamic>> _objects(Object? value) {
    if (value is! List) return const [];
    return value.map(_map).whereType<Map<String, dynamic>>().toList(growable: false);
  }

  static List<String> _titleValues(Object? value) {
    final map = _map(value);
    if (map == null) return const [];
    final normalized = map.entries
        .where((entry) => entry.value is String && (entry.value as String).trim().isNotEmpty)
        .toList();
    if (normalized.isEmpty) return const [];
    normalized.sort((a, b) {
      final aEnglish = a.key == 'en' ? 0 : 1;
      final bEnglish = b.key == 'en' ? 0 : 1;
      return aEnglish.compareTo(bEnglish);
    });
    return normalized.map((entry) => (entry.value as String).trim()).toList(growable: false);
  }

  static String? _localizedValue(Object? value, {required String preferred}) {
    final map = _map(value);
    if (map == null) return null;
    final valueInPreferredLanguage = map[preferred];
    if (valueInPreferredLanguage is String && valueInPreferredLanguage.trim().isNotEmpty) {
      return valueInPreferredLanguage.trim();
    }
    for (final entry in map.values) {
      if (entry is String && entry.trim().isNotEmpty) return entry.trim();
    }
    return null;
  }
}


/// Extended MangaDex adapter that implements series, chapter-feed, and reader
/// manifest APIs in addition to the inherited bounded search operation.
class MangaDexMultimediaProvider extends MangaDexProvider
    implements SeriesProvider, ChapterFeedProvider, ReaderPagesProvider {
  MangaDexMultimediaProvider({
    super.transport,
    super.contentRatings,
    super.resultLimit,
  });

  @override
  final ProviderDescriptor descriptor = ProviderDescriptor(
    id: 'mangadex',
    name: 'MangaDex',
    homepage: Uri(scheme: 'https', host: 'mangadex.org'),
    capabilities: {
      ProviderCapability.search,
      ProviderCapability.series,
      ProviderCapability.chapters,
      ProviderCapability.pages,
      ProviderCapability.creators,
    },
    isBuiltIn: true,
    enabledByDefault: true,
  );

  @override
  Future<ProviderResponse<WorkCandidate>> getSeries(
    String seriesId, {
    required CancellationToken cancellationToken,
  }) async {
    if (!MangaDexMultimediaProvider._isUuid(seriesId)) {
      return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Invalid MangaDex series id');
    }
    try {
      final response = await transport.get(
        Uri.parse('https://api.mangadex.org/manga/${Uri.encodeComponent(seriesId)}?includes%5B%5D=cover_art'),
        cancellationToken: cancellationToken,
      );
      final failure = _httpFailure<WorkCandidate>(response);
      if (failure != null) return failure;
      final row = MangaDexProvider._map(response.body['data']);
      final attrs = MangaDexProvider._map(row?['attributes']);
      final id = row?['id'];
      final title = MangaDexProvider._localizedValue(attrs?['title'], preferred: 'en');
      if (row == null || attrs == null || id is! String || title == null) {
        return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Malformed MangaDex series response');
      }
      final aliases = <String>[];
      for (final item in MangaDexProvider._objects(attrs['altTitles'])) {
        aliases.addAll(MangaDexProvider._titleValues(item));
      }
      final included = <String, Map<String, dynamic>>{
        for (final item in MangaDexProvider._objects(response.body['included']))
          if (item['id'] is String) item['id'] as String: item,
      };
      final cover = _coverFilename(row, included);
      final language = attrs['originalLanguage'] as String?;
      final format = switch (language) {
        'ko' => WorkFormat.manhwa,
        'zh' || 'zh-hk' => WorkFormat.manhua,
        'ja' => WorkFormat.manga,
        _ => WorkFormat.unknown,
      };
      return ProviderResponse(
        status: ProviderResultStatus.success,
        data: WorkCandidate(
          providerId: descriptor.id,
          externalId: id,
          title: title,
          alternateTitles: aliases,
          year: int.tryParse('${attrs['year'] ?? ''}'),
          format: format,
          language: language,
          description: MangaDexProvider._localizedValue(attrs['description'], preferred: 'en'),
          coverUrl: cover == null ? null : Uri.https('uploads.mangadex.org', '/covers/$id/$cover.256.jpg'),
          providerUrl: Uri.https('mangadex.org', '/title/$id'),
        ),
      );
    } on OperationCancelled catch (error) {
      return ProviderResponse(status: ProviderResultStatus.cancelled, message: error.reason);
    } on TimeoutException {
      return const ProviderResponse(status: ProviderResultStatus.timedOut, message: 'Series detail timed out');
    } on Object catch (error) {
      return ProviderResponse(status: ProviderResultStatus.failed, message: 'Series detail failed (${error.runtimeType})');
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
    if (!MangaDexMultimediaProvider._isUuid(seriesId) || limit < 1 || limit > 500 || offset < 0 ||
        translatedLanguages.isEmpty ||
        translatedLanguages.any((lang) => !RegExp(r'^[a-z]{2,3}(?:-[a-z]{2})?$').hasMatch(lang))) {
      return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Invalid chapter-feed arguments');
    }
    try {
      final params = <String>[
        MangaDexMultimediaProvider._queryParam('limit', '$limit'),
        MangaDexMultimediaProvider._queryParam('offset', '$offset'),
        MangaDexMultimediaProvider._queryParam('order[chapter]', 'desc'),
        for (final lang in translatedLanguages) MangaDexMultimediaProvider._queryParam('translatedLanguage[]', lang),
        for (final rating in contentRatings) MangaDexMultimediaProvider._queryParam('contentRating[]', rating),
      ];
      final response = await transport.get(
        Uri.parse('https://api.mangadex.org/manga/${Uri.encodeComponent(seriesId)}/feed?${params.join('&')}'),
        cancellationToken: cancellationToken,
      );
      final failure = _httpFailure<List<ChapterUnit>>(response);
      if (failure != null) return failure;
      final rows = response.body['data'];
      if (rows is! List) {
        return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Malformed chapter feed');
      }
      var dropped = false;
      final chapters = <ChapterUnit>[];
      for (final value in rows) {
        final row = MangaDexProvider._map(value);
        final id = row?['id'];
        final attrs = MangaDexProvider._map(row?['attributes']);
        if (row == null || id is! String || !MangaDexMultimediaProvider._isUuid(id) || attrs == null) {
          dropped = true;
          continue;
        }
        final lang = attrs['translatedLanguage'] is String ? attrs['translatedLanguage'] as String : 'und';
        final number = double.tryParse('${attrs['chapter'] ?? ''}');
        final title = attrs['title'] is String ? (attrs['title'] as String).trim() : '';
        final date = DateTime.tryParse('${attrs['readableAt'] ?? attrs['publishAt'] ?? ''}');
        chapters.add(ChapterUnit(
          id: id,
          editionId: 'mangadex:$seriesId:$lang',
          title: title.isEmpty ? null : title,
          chapterNumber: number,
          volumeNumber: int.tryParse('${attrs['volume'] ?? ''}'),
          kind: number == null ? ChapterKind.special : ChapterKind.regular,
          listings: [
            ChapterListing(
              providerId: descriptor.id,
              externalId: id,
              url: Uri.https('mangadex.org', '/chapter/$id'),
              languageCode: lang,
              releaseGroup: _scanlationGroup(row['relationships']),
              publishedAt: date,
            ),
          ],
        ));
      }
      final total = int.tryParse('${response.body['total'] ?? ''}');
      final more = total != null && offset + rows.length < total;
      return ProviderResponse(
        status: dropped ? ProviderResultStatus.partial : ProviderResultStatus.success,
        data: List.unmodifiable(chapters),
        message: dropped ? 'Malformed chapter rows were skipped' : (more ? 'More chapters are available' : null),
      );
    } on OperationCancelled catch (error) {
      return ProviderResponse(status: ProviderResultStatus.cancelled, message: error.reason);
    } on TimeoutException {
      return const ProviderResponse(status: ProviderResultStatus.timedOut, message: 'Chapter feed timed out');
    } on Object catch (error) {
      return ProviderResponse(status: ProviderResultStatus.failed, message: 'Chapter feed failed (${error.runtimeType})');
    }
  }

  @override
  Future<ProviderResponse<ReaderPageManifest>> getPages(
    String chapterId, {
    required CancellationToken cancellationToken,
    bool dataSaver = false,
  }) async {
    if (!MangaDexMultimediaProvider._isUuid(chapterId)) {
      return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Invalid MangaDex chapter id');
    }
    try {
      final response = await transport.get(
        Uri.parse('https://api.mangadex.org/at-home/server/${Uri.encodeComponent(chapterId)}'),
        cancellationToken: cancellationToken,
      );
      final failure = _httpFailure<ReaderPageManifest>(response);
      if (failure != null) return failure;
      final chapter = MangaDexProvider._map(response.body['chapter']);
      final baseText = response.body['baseUrl'];
      final hash = chapter?['hash'];
      final normal = chapter?['data'];
      final saver = chapter?['dataSaver'];
      if (baseText is! String || hash is! String || normal is! List || normal.isEmpty ||
          normal.any((item) => item is! String) || saver is! List || saver.any((item) => item is! String)) {
        return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Malformed MangaDex page manifest');
      }
      final base = Uri.tryParse(baseText);
      final host = base?.host.toLowerCase() ?? '';
      if (base == null || base.scheme != 'https' ||
          !(host == 'mangadex.org' || host.endsWith('.mangadex.org') || host.endsWith('.mangadex.network'))) {
        return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Untrusted reader-page host');
      }
      final manifest = ReaderPageManifest(
        chapterId: chapterId,
        baseUrl: base,
        hash: hash,
        normalFilenames: normal.cast<String>(),
        dataSaverFilenames: saver.cast<String>(),
      );
      if (manifest.urls(dataSaver: dataSaver).any((url) => url.scheme != 'https' || url.host.toLowerCase() != host)) {
        return const ProviderResponse(status: ProviderResultStatus.failed, message: 'Invalid reader-page URLs');
      }
      return ProviderResponse(status: ProviderResultStatus.success, data: manifest);
    } on OperationCancelled catch (error) {
      return ProviderResponse(status: ProviderResultStatus.cancelled, message: error.reason);
    } on TimeoutException {
      return const ProviderResponse(status: ProviderResultStatus.timedOut, message: 'Page manifest timed out');
    } on Object catch (error) {
      return ProviderResponse(status: ProviderResultStatus.failed, message: 'Page manifest failed (${error.runtimeType})');
    }
  }

  ProviderResponse<T>? _httpFailure<T>(JsonHttpResponse response) {
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.header('retry-after') ?? '');
      return ProviderResponse(
        status: ProviderResultStatus.rateLimited,
        message: 'MangaDex rate limit reached',
        retryAfter: seconds == null || seconds < 0 ? null : Duration(seconds: seconds),
      );
    }
    if (response.statusCode == 403 || response.statusCode == 451) {
      return const ProviderResponse(status: ProviderResultStatus.blocked, message: 'MangaDex did not permit this request');
    }
    if (response.statusCode != 200) {
      return ProviderResponse(status: ProviderResultStatus.failed, message: 'MangaDex returned HTTP ${response.statusCode}');
    }
    return null;
  }

  String? _scanlationGroup(Object? relationships) {
    for (final relation in MangaDexProvider._objects(relationships)) {
      if (relation['type'] == 'scanlation_group' && relation['id'] is String) return relation['id'] as String;
    }
    return null;
  }

  static bool _isUuid(String value) =>
      RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
          .hasMatch(value);

  static String _queryParam(String key, String value) =>
      '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}';
}
