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
      // A later result may have linked another provider listing to the same work.
      // Keep the newest aggregate so the universal-search card sees every source.
      if (entry != null) unique[entry.work.id] = entry;
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
  final Map<Completer<void>, CancellationToken> _activeOperations = {};

  Future<void> _writeQueue = Future<void>.value();
  Future<String>? _deviceIdFuture;
  bool _disposed = false;

  Future<CatalogSearchOutcome> searchAndCatalog(
    String query, {
    CancellationToken? cancellationToken,
  }) async {
    _ensureOpen();
    final token = cancellationToken ?? CancellationToken();
    final operation = _beginOperation(token);
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
      _endOperation(operation);
    }
  }

  Future<List<CatalogUpsertResult>> _indexBatch(SearchBatch batch) async {
    final outcomes = <CatalogUpsertResult>[];
    for (final candidate in batch.candidates) {
      // Query indexed identity terms for this listing only. Loading the entire
      // catalog for every search would grow memory and latency with library size.
      final matchPage = await database.loadCatalogCandidatesForMatching(candidate);
      final pending = await database.loadPendingIdentityReview(candidate.listingKey);
      final alreadyAssigned = matchPage.entries.where((entry) =>
          entry.listings.any((listing) => listing.listingKey == candidate.listingKey)).toList(growable: false);
      if (pending != null && alreadyAssigned.isNotEmpty) {
        // Recover the crash window between catalog commit and review deletion.
        await database.deletePendingIdentityReview(candidate.listingKey);
      }
      final index = CatalogIndex.fromEntries(
        entries: matchPage.entries,
        pendingReviews: pending == null || alreadyAssigned.isNotEmpty ? const [] : [pending],
      );
      final result = index.upsert(candidate, candidatePoolOverflow: matchPage.hasMore);
      if (result.entry != null &&
          (result.status == CatalogUpsertStatus.created || result.status == CatalogUpsertStatus.linked)) {
        await database.upsertCatalogEntry(result.entry!);
      }
      if (result.review != null) await database.savePendingIdentityReview(result.review!);
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
      final pending = await database.loadPendingIdentityReview(listingKey);
      if (pending == null) throw ArgumentError.value(listingKey, 'listingKey', 'No pending review');
      final matchPage = await database.loadCatalogCandidatesForMatching(pending.candidate);
      final assigned = matchPage.entries.where((entry) =>
          entry.listings.any((listing) => listing.listingKey == listingKey)).toList(growable: false);
      if (assigned.isNotEmpty) {
        await database.deletePendingIdentityReview(listingKey);
        return CatalogUpsertResult(
          status: CatalogUpsertStatus.alreadyKnown,
          entry: assigned.first,
          message: 'Recovered a previously committed catalog listing.',
        );
      }
      final entriesById = <String, CatalogEntry>{
        for (final entry in matchPage.entries) entry.work.id: entry,
      };
      if (targetWorkId != null && !entriesById.containsKey(targetWorkId)) {
        final target = await database.loadCatalogEntryById(targetWorkId);
        if (target != null) entriesById[target.work.id] = target;
      }
      final index = CatalogIndex.fromEntries(
        entries: entriesById.values,
        pendingReviews: [pending],
      );
      final result = index.resolveReview(
        listingKey,
        targetWorkId: targetWorkId,
        createAsDistinctWork: createAsDistinctWork,
      );
      final entry = result.entry;
      if (entry == null) throw StateError('Identity resolution did not produce a catalog entry.');
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

    _ensureOpen();
    final token = cancellationToken ?? CancellationToken();
    final operation = _beginOperation(token);
    try {
      final response = await _boundedProviderCall<WorkCandidate>(
        providerId: providerId,
        parentToken: token,
        timeoutMessage: 'Series detail timed out.',
        request: (child) => source.getSeries(
          context.listing.externalId,
          cancellationToken: child,
        ),
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
        final index = CatalogIndex.fromEntries(entries: [context.entry]);
        final entry = index.refreshKnownListing(refreshed);
        await database.upsertCatalogEntry(entry);
      });
      return response;
    } finally {
      _endOperation(operation);
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

    _ensureOpen();
    final token = cancellationToken ?? CancellationToken();
    final operation = _beginOperation(token);
    try {
      final response = await _boundedProviderCall<List<ChapterUnit>>(
        providerId: providerId,
        parentToken: token,
        timeoutMessage: 'Chapter feed timed out.',
        request: (child) => source.getChapters(
          context.listing.externalId,
          cancellationToken: child,
          translatedLanguages: translatedLanguages,
          limit: limit,
          offset: offset,
        ),
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
      _endOperation(operation);
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
      _ensureOpen();
      final token = cancellationToken ?? CancellationToken();
      final operation = _beginOperation(token);
      try {
        final response = await _boundedProviderCall<ReaderPageManifest>(
          providerId: listing.providerId,
          parentToken: token,
          timeoutMessage: 'Reader-page manifest timed out.',
          request: (child) => source.getPages(
            listing.externalId,
            cancellationToken: child,
            dataSaver: dataSaver,
          ),
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
        _endOperation(operation);
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
    final entry = await database.loadCatalogEntryById(workId);
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

  /// Gives every provider operation a hard outer timeout and cancellation
  /// race, including community adapters that accidentally ignore their token.
  /// A timed-out adapter cannot hold up the UI; compliant HTTP adapters abort
  /// their underlying request when the child token is cancelled.
  Future<ProviderResponse<T>> _boundedProviderCall<T>({
    required String providerId,
    required CancellationToken parentToken,
    required String timeoutMessage,
    required Future<ProviderResponse<T>> Function(CancellationToken token) request,
  }) async {
    final cooldown = _healthTracker.remainingCooldown(providerId);
    if (cooldown != null) {
      return ProviderResponse<T>(
        status: ProviderResultStatus.rateLimited,
        message: 'Provider temporarily paused after repeated failures.',
        retryAfter: cooldown,
      );
    }

    final child = CancellationToken();
    final cancellationResult = Completer<ProviderResponse<T>>();
    var timedOut = false;
    final detachChild = child.onCancel((reason) {
      if (cancellationResult.isCompleted) return;
      cancellationResult.complete(timedOut
          ? ProviderResponse<T>(status: ProviderResultStatus.timedOut, message: timeoutMessage)
          : ProviderResponse<T>(status: ProviderResultStatus.cancelled, message: reason));
    });
    final detachParent = parentToken.onCancel(child.cancel);
    final timer = Timer(providerTimeout, () {
      timedOut = true;
      child.cancel('Provider request timed out.');
    });

    try {
      child.throwIfCancelled();
      final requestFuture = Future<ProviderResponse<T>>.sync(() => request(child));
      final response = await Future.any<ProviderResponse<T>>([
        requestFuture,
        cancellationResult.future,
      ]);
      _healthTracker.record(providerId, response);
      return response;
    } on OperationCancelled catch (error) {
      final response = ProviderResponse<T>(
        status: timedOut
            ? ProviderResultStatus.timedOut
            : child.isCancelled
                ? ProviderResultStatus.cancelled
                : ProviderResultStatus.failed,
        message: timedOut ? timeoutMessage : error.reason,
      );
      _healthTracker.record(providerId, response);
      return response;
    } on Object {
      final response = ProviderResponse<T>(
        status: timedOut
            ? ProviderResultStatus.timedOut
            : child.isCancelled
                ? ProviderResultStatus.cancelled
                : ProviderResultStatus.failed,
        message: timedOut ? timeoutMessage : 'Provider request failed.',
      );
      _healthTracker.record(providerId, response);
      return response;
    } finally {
      timer.cancel();
      detachChild();
      detachParent();
    }
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

  Completer<void> _beginOperation(CancellationToken token) {
    _ensureOpen();
    final completion = Completer<void>();
    _activeOperations[completion] = token;
    return completion;
  }

  void _endOperation(Completer<void> completion) {
    final removed = _activeOperations.remove(completion);
    if (removed != null && !completion.isCompleted) completion.complete();
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('Catalog workflow service is disposed.');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final active = _activeOperations.entries.toList(growable: false);
    for (final token in active.map((entry) => entry.value).toSet()) {
      token.cancel('Catalog workflow service disposed');
    }
    await Future.wait(active.map((entry) => entry.key.future));
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
