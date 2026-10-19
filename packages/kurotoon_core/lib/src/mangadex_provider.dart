import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cancellation.dart';
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
