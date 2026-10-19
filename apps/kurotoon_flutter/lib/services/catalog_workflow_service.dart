import 'dart:async';
import 'dart:math';

import 'package:kurotoon_core/kurotoon_core.dart';

import '../storage/kurotoon_database.dart';

/// Search results paired with the safe catalog decisions made for each listing.
class CatalogSearchOutcome {
  CatalogSearchOutcome({
    required this.batch,
    required List<CatalogUpsertResult> catalogResults,
  }) : catalogResults = List.unmodifiable(catalogResults);

  final SearchBatch batch;
  final List<CatalogUpsertResult> catalogResults;

  List<CatalogEntry> get entries {
    final unique = <String, CatalogEntry>{};
    for (final result in catalogResults) {
      final entry = result.entry;
      if (entry != null) unique.putIfAbsent(entry.work.id, () => entry);
    }
    return List.unmodifiable(unique.values);
  }

  List<PendingIdentityReview> get reviews => List.unmodifiable(
        catalogResults.map((result) => result.review).whereType<PendingIdentityReview>(),
      );
}

/// Coordinates provider results with the persistent local catalog, chapter
/// editions, reading progress and library. Network data is normalized before
/// it is written; reader-page manifests are deliberately fetched fresh because
/// some sources issue short-lived media URLs.
class CatalogWorkflowService {
  CatalogWorkflowService({
    required this.providers,
    required this.database,
    ProviderHealthTracker? healthTracker,
    this.maxConcurrentProviders = 4,
    this.providerTimeout = const Duration(seconds: 8),
    String? deviceId,
    DateTime Function()? clock,
  })  : _healthTracker = healthTracker ?? ProviderHealthTracker(),
        _providedDeviceId = deviceId,
        _clock = clock ?? DateTime.now {
    if (maxConcurrentProviders < 1) {
      throw ArgumentError.value(maxConcurrentProviders, 'maxConcurrentProviders');
    }
    if (providerTimeout <= Duration.zero) {
      throw ArgumentError.value(providerTimeout, 'providerTimeout');
    }
    if (deviceId != null && deviceId.trim().isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Must not be blank');
    }
  }

  final ProviderRegistry providers;
  final KurotoonDatabase database;
  final ProviderHealthTracker _healthTracker;
  final int maxConcurrentProviders;
  final Duration providerTimeout;
  final String? _providedDeviceId;
  final DateTime Function() _clock;
  final Set<CancellationToken> _activeTokens = <CancellationToken>{};

  Future<void> _writeQueue = Future<void>.value();
  Future<String>? _deviceIdFuture;
  bool _disposed = false;

  Future<CatalogSearchOutcome> searchAndCatalog(
    String query, {
    CancellationToken? cancellationToken,
  }) async {
    _ensureOpen();
    final token = cancellationToken ?? CancellationToken();
    _activeTokens.add(token);
    try {
      final batch = await ProviderCoordinator(
        providers,
        maxConcurrentProviders: maxConcurrentProviders,
        providerTimeout: providerTimeout,
        healthTracker: _healthTracker,
      ).search(query, cancellationToken: token);
      _ensureOpen();
      if (token.isCancelled) {
        return CatalogSearchOutcome(batch: batch, catalogResults: const []);
      }
      final catalogResults = await _serialize(() => _indexBatch(batch));
      return CatalogSearchOutcome(batch: batch, catalogResults: catalogResults);
    } finally {
      _activeTokens.remove(token);
    }
  }

  Future<List<CatalogUpsertResult>> _indexBatch(SearchBatch batch) async {
    final persisted = await database.loadCatalog();
    final persistedReviews = await database.loadPendingIdentityReviews();
    final index = CatalogIndex.fromEntries(
      entries: persisted,
      pendingReviews: persistedReviews,
    );

    // Recover from a crash after catalog metadata committed but before the
    // corresponding review-queue row was removed.
    for (final review in persistedReviews) {
      if (index.workIdForListing(review.key) != null) {
        await database.deletePendingIdentityReview(review.key);
      }
    }

    final outcomes = <CatalogUpsertResult>[];
    for (final candidate in batch.candidates) {
      final result = index.upsert(candidate);
      if (result.entry != null &&
          (result.status == CatalogUpsertStatus.created ||
              result.status == CatalogUpsertStatus.linked)) {
        await database.upsertCatalogEntry(result.entry!);
      }
      if (result.review != null) {
        await database.savePendingIdentityReview(result.review!);
      }
      outcomes.add(result);
    }
    return List.unmodifiable(outcomes);
  }

  Future<CatalogUpsertResult> resolveIdentityReview(
    String listingKey, {
    String? targetWorkId,
    bool createAsDistinctWork = false,
  }) {
    _ensureOpen();
    return _serialize(() async {
      final index = CatalogIndex.fromEntries(
        entries: await database.loadCatalog(),
        pendingReviews: await database.loadPendingIdentityReviews(),
      );
      final result = index.resolveReview(
        listingKey,
        targetWorkId: targetWorkId,
        createAsDistinctWork: createAsDistinctWork,
      );
      final entry = result.entry;
      if (entry == null) throw StateError('Identity resolution did not produce a catalog entry.');
      // Commit the catalog outcome before removing the recoverable review row.
      // A crash in between is reconciled by _indexBatch on the next search.
      await database.upsertCatalogEntry(entry);
      await database.deletePendingIdentityReview(listingKey);
      return result;
    });
  }

  Future<ProviderResponse<WorkCandidate>> refreshSeries({
    required String workId,
    required String providerId,
    CancellationToken? cancellationToken,
  }) async {
    _ensureOpen();
    final context = await _listingContext(workId, providerId);
    final source = _provider(providerId);
    if (source == null) {
      return const ProviderResponse(
        status: ProviderResultStatus.unsupported,
        message: 'The selected source is not installed.',
      );
    }
    if (!providers.isEnabled(providerId)) {
      return const ProviderResponse(
        status: ProviderResultStatus.disabled,
        message: 'The selected source is disabled.',
      );
    }
    if (source is! SeriesProvider) {
      return const ProviderResponse(
        status: ProviderResultStatus.unsupported,
        message: 'The selected source does not provide series details.',
      );
    }

    final token = cancellationToken ?? CancellationToken();
    _activeTokens.add(token);
    try {
      final response = await source.getSeries(
        context.listing.externalId,
        cancellationToken: token,
      );
      if (!response.hasUsableData || response.data == null) return response;
      final refreshed = response.data!;
      if (refreshed.providerId != providerId ||
          refreshed.externalId != context.listing.externalId) {
        return const ProviderResponse(
          status: ProviderResultStatus.failed,
          message: 'The source returned a different series identity.',
        );
      }
      await _serialize(() async {
        final index = CatalogIndex.fromEntries(
          entries: await database.loadCatalog(),
          pendingReviews: await database.loadPendingIdentityReviews(),
        );
        final entry = index.refreshKnownListing(refreshed);
        await database.upsertCatalogEntry(entry);
      });
      return response;
    } finally {
      _activeTokens.remove(token);
    }
  }

  /// Fetches the requested chapter page and saves normalized chapters. Local
  /// IDs are namespaced by provider and external series/chapter IDs so two
  /// community sources cannot accidentally overwrite each other's rows.
  Future<ProviderResponse<List<ChapterUnit>>> fetchAndStoreChapters({
    required String workId,
    required String providerId,
    List<String> translatedLanguages = const ['en'],
    int limit = 100,
    int offset = 0,
    CancellationToken? cancellationToken,
  }) async {
    _ensureOpen();
    final context = await _listingContext(workId, providerId);
    final source = _provider(providerId);
    if (source == null) {
      return const ProviderResponse(
        status: ProviderResultStatus.unsupported,
        message: 'The selected source is not installed.',
      );
    }
    if (!providers.isEnabled(providerId)) {
      return const ProviderResponse(
        status: ProviderResultStatus.disabled,
        message: 'The selected source is disabled.',
      );
    }
    if (source is! ChapterFeedProvider) {
      return const ProviderResponse(
        status: ProviderResultStatus.unsupported,
        message: 'The selected source does not provide chapters.',
      );
    }

    final token = cancellationToken ?? CancellationToken();
    _activeTokens.add(token);
    try {
      final response = await source.getChapters(
        context.listing.externalId,
        cancellationToken: token,
        translatedLanguages: translatedLanguages,
        limit: limit,
        offset: offset,
      );
      if (!response.hasUsableData || response.data == null) return response;

      final stored = await _serialize(() => _normalizeAndStoreChapterFeed(
            context: context,
            providerId: providerId,
            chapters: response.data!,
            requestedLanguages: translatedLanguages,
          ));
      return ProviderResponse(
        status: stored.droppedRows && response.status == ProviderResultStatus.success
            ? ProviderResultStatus.partial
            : response.status,
        data: stored.chapters,
        message: stored.droppedRows
            ? 'Some unsafe or malformed chapter rows were skipped.'
            : response.message,
        retryAfter: response.retryAfter,
      );
    } finally {
      _activeTokens.remove(token);
    }
  }

  Future<_StoredChapterFeed> _normalizeAndStoreChapterFeed({
    required _ListingContext context,
    required String providerId,
    required List<ChapterUnit> chapters,
    required List<String> requestedLanguages,
  }) async {
    final editions = <String, EditionRecord>{};
    final normalizedById = <String, ChapterUnit>{};

    String editionIdFor(String language) =>
        'edition/${Uri.encodeComponent(providerId)}/'
        '${Uri.encodeComponent(context.listing.externalId)}/'
        '${Uri.encodeComponent(language)}';

    for (final rawLanguage in requestedLanguages) {
      final language = rawLanguage.trim().toLowerCase();
      if (language.isEmpty) continue;
      final id = editionIdFor(language);
      editions[id] = EditionRecord(
        id: id,
        workId: context.entry.work.id,
        title: language,
        languageCode: language,
        format: context.entry.work.format,
      );
    }

    var droppedRows = false;
    for (final raw in chapters) {
      final listings = raw.listings.where((listing) =>
          listing.providerId == providerId &&
          listing.externalId.trim().isNotEmpty &&
          listing.url.scheme == 'https' &&
          listing.url.host.isNotEmpty &&
          listing.url.userInfo.isEmpty).toList(growable: false);
      if (listings.isEmpty) {
        droppedRows = true;
        continue;
      }
      final primary = listings.first;
      final language = (primary.languageCode ?? 'und').trim().toLowerCase();
      if (language.isEmpty) {
        droppedRows = true;
        continue;
      }
      final editionId = editionIdFor(language);
      final id = 'chapter/${Uri.encodeComponent(providerId)}/'
          '${Uri.encodeComponent(primary.externalId)}';
      final normalized = ChapterUnit(
        id: id,
        editionId: editionId,
        title: raw.title,
        chapterNumber: raw.chapterNumber,
        volumeNumber: raw.volumeNumber,
        kind: raw.kind,
        miniGroupId: raw.miniGroupId,
        miniIndex: raw.miniIndex,
        miniCount: raw.miniCount,
        listings: listings,
      );
      normalizedById[id] = normalized;
      final official = listings.any((listing) => listing.isOfficialTranslation);
      final existing = editions[editionId];
      editions[editionId] = EditionRecord(
        id: editionId,
        workId: context.entry.work.id,
        title: language,
        languageCode: language,
        format: context.entry.work.format,
        isOfficial: official || (existing?.isOfficial ?? false),
      );
    }

    for (final edition in editions.values) {
      await database.upsertEdition(edition);
    }
    for (final chapter in normalizedById.values) {
      await database.upsertChapter(chapter);
    }
    return _StoredChapterFeed(
      chapters: List.unmodifiable(normalizedById.values),
      droppedRows: droppedRows,
    );
  }

  /// Returns a fresh reader manifest for a locally stored chapter. Temporary
  /// source media URLs are not persisted; call again when a chapter is opened.
  Future<ProviderResponse<ReaderPageManifest>> fetchReaderPages({
    required String workId,
    required String editionId,
    required String chapterId,
    String? providerId,
    bool dataSaver = false,
    CancellationToken? cancellationToken,
  }) async {
    _ensureOpen();
    final edition = await database.loadEdition(editionId);
    if (edition == null || edition.workId != workId) {
      return const ProviderResponse(
        status: ProviderResultStatus.failed,
        message: 'The selected edition does not belong to this series.',
      );
    }
    final chapters = await database.loadChapters(editionId);
    ChapterUnit? chapter;
    for (final item in chapters) {
      if (item.id == chapterId) {
        chapter = item;
        break;
      }
    }
    if (chapter == null) {
      return const ProviderResponse(
        status: ProviderResultStatus.failed,
        message: 'The chapter is not present in the local chapter index.',
      );
    }

    for (final listing in chapter.listings) {
      if (providerId != null && listing.providerId != providerId) continue;
      final source = _provider(listing.providerId);
      if (source == null || source is! ReaderPagesProvider) continue;
      if (!providers.isEnabled(listing.providerId)) continue;
      final token = cancellationToken ?? CancellationToken();
      _activeTokens.add(token);
      try {
        final response = await source.getPages(
          listing.externalId,
          cancellationToken: token,
          dataSaver: dataSaver,
        );
        if (!response.hasUsableData || response.data == null) return response;
        final manifest = response.data!;
        if (manifest.chapterId != listing.externalId ||
            manifest.urls(dataSaver: dataSaver).any((url) =>
                url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty)) {
          return const ProviderResponse(
            status: ProviderResultStatus.failed,
            message: 'The source returned an unsafe reader-page manifest.',
          );
        }
        return response;
      } finally {
        _activeTokens.remove(token);
      }
    }
    return ProviderResponse(
      status: ProviderResultStatus.unsupported,
      message: providerId == null
          ? 'No installed, enabled source can open this chapter.'
          : 'The selected source cannot open this chapter.',
    );
  }

  Future<LibraryRecord> addToLibrary({
    required String workId,
    required String editionId,
    LibraryStatus status = LibraryStatus.planned,
  }) async {
    _ensureOpen();
    final edition = await database.loadEdition(editionId);
    if (edition == null || edition.workId != workId) {
      throw ArgumentError.value(editionId, 'editionId', 'Edition does not belong to the selected series.');
    }
    final library = await database.loadLibrary();
    LibraryRecord? existing;
    for (final record in library) {
      if (record.workId == workId && record.editionId == editionId) {
        existing = record;
        break;
      }
    }
    final maximumOrder = library.fold<int>(
      0,
      (maximum, record) => record.sortOrder > maximum ? record.sortOrder : maximum,
    );
    final record = LibraryRecord(
      workId: workId,
      editionId: editionId,
      status: status,
      addedAt: existing?.addedAt ?? _clock(),
      lastOpenedAt: existing?.lastOpenedAt,
      sortOrder: existing?.sortOrder ?? maximumOrder + 10,
    );
    await database.putLibraryRecord(record);
    return record;
  }

  Future<void> setLibraryStatus({
    required String workId,
    required String editionId,
    required LibraryStatus status,
  }) async {
    _ensureOpen();
    final library = await database.loadLibrary();
    LibraryRecord? current;
    for (final record in library) {
      if (record.workId == workId && record.editionId == editionId) {
        current = record;
        break;
      }
    }
    if (current == null) throw StateError('Series edition is not in the library.');
    await database.putLibraryRecord(LibraryRecord(
      workId: current.workId,
      editionId: current.editionId,
      status: status,
      addedAt: current.addedAt,
      lastOpenedAt: current.lastOpenedAt,
      sortOrder: current.sortOrder,
    ));
  }

  Future<void> removeFromLibrary({
    required String workId,
    required String editionId,
  }) {
    _ensureOpen();
    return database.removeLibraryRecord(workId, editionId);
  }

  Future<ReadingProgress> saveProgress({
    required String workId,
    required String editionId,
    required String chapterId,
    required double fraction,
    String? anchor,
    int? revision,
  }) async {
    _ensureOpen();
    final edition = await database.loadEdition(editionId);
    if (edition == null || edition.workId != workId) {
      throw ArgumentError.value(editionId, 'editionId', 'Edition does not belong to the selected series.');
    }
    final chapters = await database.loadChapters(editionId);
    if (!chapters.any((chapter) => chapter.id == chapterId)) {
      throw ArgumentError.value(chapterId, 'chapterId', 'Chapter does not belong to this edition.');
    }

    final current = await database.loadProgress(workId, editionId);
    final incoming = ReadingProgress(
      workId: workId,
      editionId: editionId,
      chapterId: chapterId,
      anchor: anchor,
      fraction: fraction,
      updatedAt: _clock().toUtc(),
      deviceId: await _installationDeviceId(),
      revision: revision ?? ((current?.revision ?? 0) + 1),
    );
    return database.saveProgress(incoming);
  }

  Future<ReadingProgress?> loadProgress(String workId, String editionId) async {
    _ensureOpen();
    final edition = await database.loadEdition(editionId);
    if (edition == null || edition.workId != workId) return null;
    return database.loadProgress(workId, editionId);
  }

  Future<String> _installationDeviceId() {
    return _deviceIdFuture ??= _loadOrCreateDeviceId();
  }

  Future<String> _loadOrCreateDeviceId() async {
    if (_providedDeviceId != null) return _providedDeviceId;
    const settingKey = 'app.installationDeviceId';
    final saved = await database.getSetting<String>(settingKey);
    if (saved != null && saved.trim().isNotEmpty) return saved;
    final random = Random.secure();
    final created = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await database.setSetting(settingKey, created);
    return created;
  }

  Future<_ListingContext> _listingContext(String workId, String providerId) async {
    final catalog = await database.loadCatalog();
    CatalogEntry? entry;
    for (final candidate in catalog) {
      if (candidate.work.id == workId) {
        entry = candidate;
        break;
      }
    }
    if (entry == null) throw ArgumentError.value(workId, 'workId', 'Series is not in the catalog.');
    for (final listing in entry.listings) {
      if (listing.providerId == providerId) return _ListingContext(entry: entry, listing: listing);
    }
    throw ArgumentError.value(providerId, 'providerId', 'Series has no listing from this source.');
  }

  SourceProvider? _provider(String providerId) {
    for (final provider in providers.all) {
      if (provider.descriptor.id == providerId) return provider;
    }
    return null;
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    _ensureOpen();
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        _ensureOpen();
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('Catalog workflow service is disposed.');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final token in _activeTokens.toList()) {
      token.cancel('Catalog workflow service disposed');
    }
    await _writeQueue;
  }
}

class _ListingContext {
  const _ListingContext({required this.entry, required this.listing});
  final CatalogEntry entry;
  final WorkCandidate listing;
}

class _StoredChapterFeed {
  const _StoredChapterFeed({required this.chapters, required this.droppedRows});
  final List<ChapterUnit> chapters;
  final bool droppedRows;
}
