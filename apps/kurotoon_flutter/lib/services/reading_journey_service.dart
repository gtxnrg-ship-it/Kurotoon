import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kurotoon_core/kurotoon_core.dart';

import '../storage/kurotoon_database.dart';

class ReadingJourneyException implements Exception {
  const ReadingJourneyException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SeriesOpenResult {
  const SeriesOpenResult({
    required this.details,
    required this.catalogResult,
    required this.detailsRefreshed,
    this.warning,
  });

  final WorkCandidate details;
  final CatalogUpsertResult catalogResult;
  final bool detailsRefreshed;
  final String? warning;
}

class ChapterRefreshResult {
  const ChapterRefreshResult({
    required this.providerId,
    required this.workId,
    required this.chapters,
    required this.editionIds,
    required this.requestedOffset,
    required this.nextOffset,
    this.warning,
  });

  final String providerId;
  final String workId;
  final List<ChapterUnit> chapters;
  final Set<String> editionIds;
  final int requestedOffset;
  final int? nextOffset;
  final String? warning;

  bool get hasMore => nextOffset != null;
}

class ReadingResumeTarget {
  const ReadingResumeTarget({
    required this.progress,
    required this.chapter,
    this.staleReason,
  });

  final ReadingProgress progress;
  final ChapterUnit? chapter;
  final String? staleReason;

  bool get canResume => chapter != null && staleReason == null;
}

class LibraryBook {
  const LibraryBook({
    required this.record,
    required this.catalogEntry,
    required this.edition,
    required this.progress,
  });

  final LibraryRecord record;
  final CatalogEntry? catalogEntry;
  final EditionRecord? edition;
  final ReadingProgress? progress;
}

/// A resumable history item. It intentionally does not imply library membership.
class RecentReadingEntry {
  const RecentReadingEntry({
    required this.catalogEntry,
    required this.edition,
    required this.target,
  });

  final CatalogEntry? catalogEntry;
  final EditionRecord? edition;
  final ReadingResumeTarget target;
}

/// Connects the existing provider, catalog and storage foundations into a
/// testable read journey. Page manifests are intentionally fetched fresh:
/// MangaDex at-home URLs are temporary and are never stored as durable metadata.
class ReadingJourneyService {
  ReadingJourneyService({
    required this.providers,
    required this.database,
    ProviderCoordinator Function()? coordinatorFactory,
    ProviderHealthTracker? healthTracker,
    Future<String> Function()? deviceIdProvider,
    this.requestTimeout = const Duration(seconds: 15),
    this.defaultChapterPageSize = 100,
  })  : healthTracker = healthTracker,
        _deviceIdProvider = deviceIdProvider {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(requestTimeout, 'requestTimeout');
    }
    if (defaultChapterPageSize < 1 || defaultChapterPageSize > 500) {
      throw ArgumentError.value(defaultChapterPageSize, 'defaultChapterPageSize');
    }
    _coordinatorFactory = coordinatorFactory ??
        (() => ProviderCoordinator(providers, healthTracker: healthTracker));
  }

  final ProviderRegistry providers;
  final KurotoonDatabase database;
  final ProviderHealthTracker? healthTracker;
  final Duration requestTimeout;
  final int defaultChapterPageSize;
  final Future<String> Function()? _deviceIdProvider;
  late final ProviderCoordinator Function() _coordinatorFactory;

  String? _resolvedDeviceId;
  bool _disposed = false;
  Future<void> _catalogWriteQueue = Future<void>.value();

  Future<SearchBatch> search(
    String query, {
    CancellationToken? cancellationToken,
  }) {
    _ensureActive();
    return _coordinatorFactory().search(
      query,
      cancellationToken: cancellationToken,
    );
  }

  /// Fetches source detail when that provider has a detail API, then safely
  /// creates/updates the cross-source catalog identity for the selected listing.
  Future<SeriesOpenResult> openSeries(
    WorkCandidate listing, {
    CancellationToken? cancellationToken,
  }) async {
    _ensureActive();
    final token = cancellationToken ?? CancellationToken();
    token.throwIfCancelled();
    final provider = _activeProvider(listing.providerId);
    var details = listing;
    var detailsRefreshed = false;
    String? warning;

    if (provider is SeriesProvider &&
        provider.descriptor.supports(ProviderCapability.series)) {
      try {
        final response = await _invoke(
          providerId: provider.descriptor.id,
          operation: 'Series details',
          token: token,
          request: () => provider.getSeries(
            listing.externalId,
            cancellationToken: token,
          ),
        );
        if (!response.hasUsableData || response.data == null) {
          warning = response.message ?? 'Series details are unavailable; the selected search result was retained.';
        } else if (response.data!.providerId != listing.providerId ||
            response.data!.externalId != listing.externalId) {
          warning = 'The source returned a different listing identity; the selected search result was retained.';
        } else {
          details = response.data!;
          detailsRefreshed = true;
        }
      } on OperationCancelled {
        rethrow;
      } on Object catch (error) {
        warning = 'Series details refresh failed (${error.runtimeType}); the selected search result was retained.';
      }
    }

    final catalogResult = await _upsertListing(details);
    return SeriesOpenResult(
      details: details,
      catalogResult: catalogResult,
      detailsRefreshed: detailsRefreshed,
      warning: warning,
    );
  }

  /// Persists a selected search result without making an additional network call.
  Future<CatalogUpsertResult> saveListing(WorkCandidate candidate) {
    _ensureActive();
    return _upsertListing(candidate);
  }

  Future<CatalogUpsertResult> _upsertListing(WorkCandidate candidate) {
    _ensureActive();
    return _serializeCatalogWrite(() => _upsertListingSerialized(candidate));
  }

  Future<CatalogUpsertResult> _upsertListingSerialized(WorkCandidate candidate) async {
    final matchPage = await database.loadCatalogCandidatesForMatching(candidate);
    final priorEntry = _entryForListing(matchPage.entries, candidate.listingKey);
    final pending = await database.loadPendingIdentityReview(candidate.listingKey);

    if (priorEntry != null) {
      final aliases = <String>{...priorEntry.work.alternateTitles};
      if (WorkIdentityMatcher.normalizeTitle(candidate.title) !=
          WorkIdentityMatcher.normalizeTitle(priorEntry.work.title)) {
        aliases.add(candidate.title);
      }
      aliases.addAll(candidate.alternateTitles);
      final creators = <String>{...priorEntry.work.creatorNames, ...candidate.creatorNames};
      final refreshedWork = WorkRecord(
        id: priorEntry.work.id,
        title: priorEntry.work.title,
        alternateTitles: aliases.toList(),
        creatorNames: creators.toList(),
        year: priorEntry.work.year ?? candidate.year,
        format: priorEntry.work.format == WorkFormat.unknown ? candidate.format : priorEntry.work.format,
        lockedDistinctIdentity: priorEntry.work.lockedDistinctIdentity,
      );
      final refreshedListings = priorEntry.listings
          .map((item) => item.listingKey == candidate.listingKey ? candidate : item)
          .toList();
      final refreshedEntry = CatalogEntry(work: refreshedWork, listings: refreshedListings, verified: priorEntry.verified);
      await database.upsertCatalogEntry(refreshedEntry);
      if (pending != null) await database.deletePendingIdentityReview(candidate.listingKey);
      return CatalogUpsertResult(
        status: CatalogUpsertStatus.alreadyKnown,
        entry: refreshedEntry,
        message: 'Updated the existing source listing.',
      );
    }

    if (pending != null) {
      return CatalogUpsertResult(
        status: CatalogUpsertStatus.alreadyKnown,
        review: pending,
        message: 'This listing is already awaiting identity review.',
      );
    }

    const matcher = WorkIdentityMatcher();
    final safeMatches = <CatalogEntry>[];
    final reviewMatches = <IdentityDecision>[];
    for (final entry in matchPage.entries) {
      final decision = matcher.compare(entry.work, candidate);
      if (decision.verdict == IdentityVerdict.safeMatch) {
        safeMatches.add(entry);
      } else if (decision.verdict == IdentityVerdict.needsReview) {
        reviewMatches.add(decision);
      }
    }

    if (!matchPage.hasMore && safeMatches.length == 1 && reviewMatches.isEmpty) {
      final target = safeMatches.single;
      final aliases = <String>{...target.work.alternateTitles};
      if (WorkIdentityMatcher.normalizeTitle(candidate.title) !=
          WorkIdentityMatcher.normalizeTitle(target.work.title)) {
        aliases.add(candidate.title);
      }
      aliases.addAll(candidate.alternateTitles);
      final creators = <String>{...target.work.creatorNames, ...candidate.creatorNames};
      final linked = CatalogEntry(
        work: WorkRecord(
          id: target.work.id,
          title: target.work.title,
          alternateTitles: aliases.toList(),
          creatorNames: creators.toList(),
          year: target.work.year ?? candidate.year,
          format: target.work.format == WorkFormat.unknown ? candidate.format : target.work.format,
          lockedDistinctIdentity: target.work.lockedDistinctIdentity,
        ),
        listings: [...target.listings, candidate],
        verified: target.verified,
      );
      await database.upsertCatalogEntry(linked);
      return CatalogUpsertResult(status: CatalogUpsertStatus.linked, entry: linked);
    }

    if (matchPage.hasMore || safeMatches.length > 1 || reviewMatches.isNotEmpty) {
      final review = PendingIdentityReview(
        key: candidate.listingKey,
        candidate: candidate,
        possibleMatches: [
          ...safeMatches.map((entry) => matcher.compare(entry.work, candidate)),
          ...reviewMatches,
        ],
      );
      await database.savePendingIdentityReview(review);
      return CatalogUpsertResult(
        status: CatalogUpsertStatus.reviewRequired,
        review: review,
        message: matchPage.hasMore
            ? 'The catalog has too many possible matches to resolve safely automatically.'
            : 'A possible duplicate needs an explicit decision; no automatic merge was performed.',
      );
    }

    final created = CatalogEntry(
      work: WorkRecord(
        id: _stableId('work', candidate.listingKey),
        title: candidate.title,
        alternateTitles: candidate.alternateTitles,
        creatorNames: candidate.creatorNames,
        year: candidate.year,
        format: candidate.format,
      ),
      listings: [candidate],
    );
    await database.upsertCatalogEntry(created);
    return CatalogUpsertResult(status: CatalogUpsertStatus.created, entry: created);
  }

  /// Resolves a persisted identity review by explicitly linking to an existing
  /// work or affirming that the listing is a separate, locked identity.
  Future<CatalogUpsertResult> resolveIdentityReview(
    String listingKey, {
    String? targetWorkId,
    bool createAsDistinctWork = false,
  }) {
    _ensureActive();
    return _serializeCatalogWrite(() => _resolveIdentityReviewSerialized(
      listingKey,
      targetWorkId: targetWorkId,
      createAsDistinctWork: createAsDistinctWork,
    ));
  }

  Future<CatalogUpsertResult> _resolveIdentityReviewSerialized(
    String listingKey, {
    String? targetWorkId,
    bool createAsDistinctWork = false,
  }) async {
    if ((targetWorkId == null) == !createAsDistinctWork) {
      throw ArgumentError('Choose exactly one of targetWorkId or createAsDistinctWork.');
    }
    final review = await database.loadPendingIdentityReview(listingKey);
    if (review == null) throw ArgumentError.value(listingKey, 'listingKey', 'No pending identity review exists.');

    final matchPage = await database.loadCatalogCandidatesForMatching(review.candidate);
    final alreadyKnown = _entryForListing(matchPage.entries, listingKey);
    if (alreadyKnown != null) {
      await database.deletePendingIdentityReview(listingKey);
      return CatalogUpsertResult(
        status: CatalogUpsertStatus.alreadyKnown,
        entry: alreadyKnown,
        message: 'The listing was already resolved in the catalog.',
      );
    }

    if (targetWorkId != null) {
      CatalogEntry? target;
      for (final entry in matchPage.entries) {
        if (entry.work.id == targetWorkId) { target = entry; break; }
      }
      target ??= await database.loadCatalogEntryById(targetWorkId);
      if (target == null) throw ArgumentError.value(targetWorkId, 'targetWorkId', 'Unknown catalog work.');
      final aliases = <String>{...target.work.alternateTitles};
      if (WorkIdentityMatcher.normalizeTitle(review.candidate.title) !=
          WorkIdentityMatcher.normalizeTitle(target.work.title)) aliases.add(review.candidate.title);
      aliases.addAll(review.candidate.alternateTitles);
      final creators = <String>{...target.work.creatorNames, ...review.candidate.creatorNames};
      final linked = CatalogEntry(
        work: WorkRecord(
          id: target.work.id,
          title: target.work.title,
          alternateTitles: aliases.toList(),
          creatorNames: creators.toList(),
          year: target.work.year ?? review.candidate.year,
          format: target.work.format == WorkFormat.unknown ? review.candidate.format : target.work.format,
          lockedDistinctIdentity: target.work.lockedDistinctIdentity,
        ),
        listings: [...target.listings, review.candidate],
        verified: target.verified,
      );
      await database.upsertCatalogEntry(linked);
      await database.deletePendingIdentityReview(listingKey);
      return CatalogUpsertResult(status: CatalogUpsertStatus.linked, entry: linked);
    }

    final separate = CatalogEntry(
      work: WorkRecord(
        id: _stableId('work', review.candidate.listingKey),
        title: review.candidate.title,
        alternateTitles: review.candidate.alternateTitles,
        creatorNames: review.candidate.creatorNames,
        year: review.candidate.year,
        format: review.candidate.format,
        lockedDistinctIdentity: true,
      ),
      listings: [review.candidate],
    );
    await database.upsertCatalogEntry(separate);
    await database.deletePendingIdentityReview(listingKey);
    return CatalogUpsertResult(status: CatalogUpsertStatus.created, entry: separate);
  }

  /// Fetches one bounded chapter page. Call again with [nextOffset] to load more;
  /// large feeds are never fetched in an unbounded loop.
  Future<ChapterRefreshResult> refreshChapters({
    required String workId,
    String? providerId,
    List<String> translatedLanguages = const ['en'],
    int offset = 0,
    int? limit,
    CancellationToken? cancellationToken,
  }) async {
    _ensureActive();
    final token = cancellationToken ?? CancellationToken();
    token.throwIfCancelled();
    final pageSize = limit ?? defaultChapterPageSize;
    if (offset < 0 || pageSize < 1 || pageSize > 500) {
      throw ArgumentError('Chapter pagination requires offset >= 0 and limit between 1 and 500.');
    }
    final languages = translatedLanguages
        .map((language) => language.trim().toLowerCase())
        .toSet()
        .toList();
    if (languages.isEmpty ||
        languages.length > 8 ||
        languages.any((language) =>
            !RegExp(r'^[a-z]{2,3}(?:-[a-z]{2})?$').hasMatch(language))) {
      throw ArgumentError.value(translatedLanguages, 'translatedLanguages');
    }

    final entry = await database.loadCatalogEntryById(workId);
    if (entry == null) throw ArgumentError.value(workId, 'workId', 'Unknown catalog work.');

    final selectedListing = _selectListing(
      entry,
      providerId: providerId,
      capability: ProviderCapability.chapters,
    );
    final provider = _activeProvider(selectedListing.providerId);
    if (provider is! ChapterFeedProvider) {
      throw ReadingJourneyException('The selected source does not provide chapter feeds.');
    }

    final response = await _invoke(
      providerId: provider.descriptor.id,
      operation: 'Chapter feed',
      token: token,
      request: () => provider.getChapters(
        selectedListing.externalId,
        cancellationToken: token,
        translatedLanguages: List.unmodifiable(languages),
        limit: pageSize,
        offset: offset,
      ),
    );
    final page = _requireUsableList(response, 'Chapter feed');
    final normalized = <ChapterUnit>[];
    final seen = <String>{};
    final warnings = <String>[];
    if (response.message != null && response.message!.trim().isNotEmpty) {
      warnings.add(response.message!.trim());
    }

    for (final rawChapter in page) {
      final matchingListings = rawChapter.listings.where((listing) {
        if (listing.providerId != provider.descriptor.id) return false;
        final language = listing.languageCode?.trim().toLowerCase();
        return language == null || languages.contains(language);
      }).toList();
      if (matchingListings.isEmpty) {
        warnings.add('A chapter without matching source provenance or requested language was skipped.');
        continue;
      }
      // A source may return one chapter record with multiple translation
      // listings. Keep each language as a distinct edition and retain only the
      // listing that actually belongs to that edition.
      for (final sourceListing in matchingListings) {
        if (!seen.add(sourceListing.key)) continue;
        final language = (sourceListing.languageCode ?? languages.first).trim().toLowerCase();
        if (!languages.contains(language)) continue;
        final editionId = _editionId(
          workId: workId,
          providerId: provider.descriptor.id,
          seriesExternalId: selectedListing.externalId,
          language: language,
        );
        final localChapter = ChapterUnit(
          id: _stableId('chapter', sourceListing.key),
          editionId: editionId,
          title: rawChapter.title,
          chapterNumber: rawChapter.chapterNumber,
          volumeNumber: rawChapter.volumeNumber,
          kind: rawChapter.kind,
          miniGroupId: rawChapter.miniGroupId == null
              ? null
              : _stableId('mini', provider.descriptor.id + ':' + rawChapter.miniGroupId!),
          miniIndex: rawChapter.miniIndex,
          miniCount: rawChapter.miniCount,
          listings: [sourceListing],
        );
        normalized.add(localChapter);
      }
    }

    final editions = <String, EditionRecord>{};
    for (final chapter in normalized) {
      final language = chapter.listings.first.languageCode ?? translatedLanguages.first;
      editions[chapter.editionId] = EditionRecord(
        id: chapter.editionId,
        workId: workId,
        title: language,
        languageCode: language,
        releaseYear: entry.work.year,
        format: entry.work.format,
      );
    }

    for (final edition in editions.values) {
      await database.upsertEdition(edition);
    }
    for (final chapter in normalized) {
      await database.upsertChapter(chapter);
    }

    final hasMore = page.length >= pageSize ||
        response.status == ProviderResultStatus.partial ||
        (response.message?.contains('More chapters are available') ?? false);
    return ChapterRefreshResult(
      providerId: provider.descriptor.id,
      workId: workId,
      chapters: List.unmodifiable(normalized),
      editionIds: Set.unmodifiable(editions.keys),
      requestedOffset: offset,
      nextOffset: hasMore ? offset + pageSize : null,
      warning: warnings.isEmpty ? null : warnings.toSet().join(' '),
    );
  }

  Future<List<ChapterUnit>> loadStoredChapters(String editionId) {
    _ensureActive();
    return database.loadChapters(editionId);
  }

  /// Fetches a fresh page manifest from the selected source. Returned URLs are
  /// transient reader data; callers must not write them to long-lived metadata.
  Future<ReaderPageManifest> loadReaderPages(
    ChapterUnit chapter, {
    String? providerId,
    bool dataSaver = false,
    CancellationToken? cancellationToken,
  }) async {
    _ensureActive();
    final token = cancellationToken ?? CancellationToken();
    token.throwIfCancelled();
    final selectedListing = _selectChapterListing(chapter, providerId: providerId);
    final provider = _activeProvider(selectedListing.providerId);
    if (provider is! ReaderPagesProvider) {
      throw ReadingJourneyException('The selected source cannot supply reader pages.');
    }
    final response = await _invoke(
      providerId: provider.descriptor.id,
      operation: 'Reader page manifest',
      token: token,
      request: () => provider.getPages(
        selectedListing.externalId,
        cancellationToken: token,
        dataSaver: dataSaver,
      ),
    );
    final manifest = _requireUsable(response, 'Reader page manifest');
    if (manifest.chapterId != selectedListing.externalId) {
      throw const ReadingJourneyException('The source returned a page manifest for a different chapter.');
    }
    final base = manifest.baseUrl;
    final safe = const RepositoryPolicy().validate(base.toString());
    if (!safe.allowed) {
      throw ReadingJourneyException('The reader page host was rejected: ' + safe.reason);
    }
    return manifest;
  }

  Future<ChapterUnit?> adjacentChapter({
    required String editionId,
    required String currentChapterId,
    required int direction,
  }) async {
    _ensureActive();
    if (direction != -1 && direction != 1) {
      throw ArgumentError.value(direction, 'direction', 'Must be -1 (previous) or 1 (next).');
    }
    final chapters = await database.loadChapters(editionId);
    final index = chapters.indexWhere((chapter) => chapter.id == currentChapterId);
    if (index < 0) {
      throw ArgumentError.value(currentChapterId, 'currentChapterId', 'Chapter is not in this edition.');
    }
    final next = index + direction;
    return next < 0 || next >= chapters.length ? null : chapters[next];
  }

  /// Adds a work/source/language combination to the local library. Creating the
  /// edition here means a work can be saved before its chapter feed is fetched.
  Future<LibraryRecord> addToLibrary({
    required String workId,
    required String providerId,
    String languageCode = 'en',
    LibraryStatus status = LibraryStatus.planned,
  }) async {
    _ensureActive();
    final language = languageCode.toLowerCase().trim();
    if (!RegExp(r'^[a-z]{2,3}(?:-[a-z]{2})?$').hasMatch(language)) {
      throw ArgumentError.value(languageCode, 'languageCode');
    }
    final entry = await database.loadCatalogEntryById(workId);
    if (entry == null) throw ArgumentError.value(workId, 'workId', 'Unknown catalog work.');
    final listings = entry.listings.where((item) => item.providerId == providerId);
    if (listings.isEmpty) {
      throw ArgumentError.value(providerId, 'providerId', 'The work has no listing from this source.');
    }
    final listing = listings.first;
    final editionId = _editionId(
      workId: workId,
      providerId: providerId,
      seriesExternalId: listing.externalId,
      language: language,
    );
    await database.upsertEdition(EditionRecord(
      id: editionId,
      workId: workId,
      title: language,
      languageCode: language,
      releaseYear: entry.work.year,
      format: entry.work.format,
    ));

    final existing = await database.loadLibraryRecord(workId, editionId);
    if (existing != null) return existing;
    final all = await database.loadLibrary();
    final maxOrder = all.fold<int>(-10, (maxValue, record) =>
        record.sortOrder > maxValue ? record.sortOrder : maxValue);
    final record = LibraryRecord(
      workId: workId,
      editionId: editionId,
      status: status,
      addedAt: DateTime.now().toUtc(),
      sortOrder: maxOrder + 10,
    );
    await database.putLibraryRecord(record);
    return record;
  }

  Future<LibraryRecord> updateLibraryStatus({
    required String workId,
    required String editionId,
    required LibraryStatus status,
  }) async {
    _ensureActive();
    final record = await database.loadLibraryRecord(workId, editionId);
    if (record == null) {
      throw StateError('This edition is not in the library.');
    }
    final updated = LibraryRecord(
      workId: record.workId,
      editionId: record.editionId,
      status: status,
      addedAt: record.addedAt,
      lastOpenedAt: record.lastOpenedAt,
      sortOrder: record.sortOrder,
    );
    await database.putLibraryRecord(updated);
    return updated;
  }

  Future<void> removeFromLibrary({
    required String workId,
    required String editionId,
  }) async {
    _ensureActive();
    await database.removeLibraryRecord(workId, editionId);
  }

  Future<List<LibraryBook>> loadLibrary({LibraryStatus? status}) async {
    _ensureActive();
    final rows = await database.loadLibrary(status: status);
    final workIds = rows.map((record) => record.workId).toSet();
    final loadedEntries = await Future.wait(workIds.map(database.loadCatalogEntryById));
    final byWork = <String, CatalogEntry>{
      for (final entry in loadedEntries.whereType<CatalogEntry>()) entry.work.id: entry,
    };
    final books = await Future.wait(rows.map((record) async {
      final entry = byWork[record.workId];
      final edition = await database.loadEdition(record.editionId);
      final progress = await database.loadProgress(record.workId, record.editionId);
      return LibraryBook(
        record: record,
        catalogEntry: entry,
        edition: edition,
        progress: progress,
      );
    }));
    return List.unmodifiable(books);
  }

  /// Returns a bounded resume shelf ordered by the last saved reading activity.
  /// Progress is a separate durable record, so removing a work from the library
  /// does not erase the user's reading history.
  Future<List<RecentReadingEntry>> loadRecentReading({int limit = 8}) async {
    _ensureActive();
    if (limit < 1 || limit > 50) {
      throw ArgumentError.value(limit, 'limit', 'Must be between 1 and 50.');
    }
    final progressRows = await database.loadRecentProgress(limit: limit);
    final recent = <RecentReadingEntry>[];
    for (final progress in progressRows) {
      try {
        final resolved = await Future.wait<Object?>([
          database.loadCatalogEntryById(progress.workId),
          database.loadEdition(progress.editionId),
          loadResumeTarget(workId: progress.workId, editionId: progress.editionId),
        ]);
        final target = resolved[2] as ReadingResumeTarget?;
        if (target == null) continue;
        recent.add(RecentReadingEntry(
          catalogEntry: resolved[0] as CatalogEntry?,
          edition: resolved[1] as EditionRecord?,
          target: target,
        ));
      } on Object {
        // One stale/corrupt history item must not hide other valid recent items.
        continue;
      }
    }
    return List<RecentReadingEntry>.unmodifiable(recent);
  }

  /// Stores local progress only for a real chapter in the selected edition and
  /// keeps an existing library row's status/order while updating last-opened.
  Future<ReadingProgress> saveReadingProgress({
    required String workId,
    required String editionId,
    required String chapterId,
    required double fraction,
    String? anchor,
  }) async {
    _ensureActive();
    final edition = await database.loadEdition(editionId);
    if (edition == null || edition.workId != workId) {
      throw StateError('Reading progress must refer to an edition belonging to the selected work.');
    }
    if (!await database.hasChapterInEdition(editionId, chapterId)) {
      throw StateError('Reading progress must refer to a chapter in the selected edition.');
    }

    final current = await database.loadProgress(workId, editionId);
    var updatedAt = DateTime.now().toUtc();
    if (current != null && !updatedAt.isAfter(current.updatedAt.toUtc())) {
      updatedAt = current.updatedAt.toUtc().add(const Duration(microseconds: 1));
    }
    final incoming = ReadingProgress(
      workId: workId,
      editionId: editionId,
      chapterId: chapterId,
      fraction: fraction,
      anchor: anchor,
      updatedAt: updatedAt,
      deviceId: await _getDeviceId(),
      revision: (current?.revision ?? 0) + 1,
    );
    final saved = await database.saveProgress(incoming);
    final libraryRecord = await database.loadLibraryRecord(workId, editionId);
    if (libraryRecord != null) {
      await database.putLibraryRecord(LibraryRecord(
        workId: libraryRecord.workId,
        editionId: libraryRecord.editionId,
        status: libraryRecord.status,
        addedAt: libraryRecord.addedAt,
        lastOpenedAt: updatedAt,
        sortOrder: libraryRecord.sortOrder,
      ));
    }
    return saved;
  }

  Future<ReadingResumeTarget?> loadResumeTarget({
    required String workId,
    required String editionId,
  }) async {
    _ensureActive();
    final progress = await database.loadProgress(workId, editionId);
    if (progress == null) return null;
    final edition = await database.loadEdition(editionId);
    if (edition == null || edition.workId != workId) {
      return ReadingResumeTarget(
        progress: progress,
        chapter: null,
        staleReason: 'The saved edition no longer belongs to this work.',
      );
    }
    final chapters = await database.loadChapters(editionId);
    ChapterUnit? chapter;
    for (final candidate in chapters) {
      if (candidate.id == progress.chapterId) {
        chapter = candidate;
        break;
      }
    }
    if (chapter == null) {
      return ReadingResumeTarget(
        progress: progress,
        chapter: null,
        staleReason: 'The saved chapter is not in the local chapter list. Refresh the source before resuming.',
      );
    }
    return ReadingResumeTarget(progress: progress, chapter: chapter);
  }

  Future<void> _recordProviderResponse<T>(String providerId, ProviderResponse<T> response) async {
    healthTracker?.record(
      providerId,
      ProviderResponse<Object?>(
        status: response.status,
        message: response.message,
        retryAfter: response.retryAfter,
      ),
    );
  }

  Future<ProviderResponse<T>> _invoke<T>({
    required String providerId,
    required String operation,
    required CancellationToken token,
    required Future<ProviderResponse<T>> Function() request,
  }) async {
    try {
      final response = await request().timeout(
        requestTimeout,
        onTimeout: () {
          token.cancel(operation + ' timed out');
          throw TimeoutException(operation + ' timed out', requestTimeout);
        },
      );
      await _recordProviderResponse(providerId, response);
      return response;
    } on TimeoutException {
      healthTracker?.record(
        providerId,
        ProviderResponse<Object?>(
          status: ProviderResultStatus.timedOut,
          message: operation + ' timed out',
        ),
      );
      rethrow;
    } on OperationCancelled {
      rethrow;
    } on Object catch (error) {
      healthTracker?.record(
        providerId,
        ProviderResponse<Object?>(
          status: ProviderResultStatus.failed,
          message: operation + ' failed (' + error.runtimeType.toString() + ')',
        ),
      );
      rethrow;
    }
  }

  SourceProvider _activeProvider(String providerId) {
    SourceProvider? selected;
    for (final provider in providers.all) {
      if (provider.descriptor.id == providerId) {
        selected = provider;
        break;
      }
    }
    if (selected == null) throw StateError('Source is not installed: ' + providerId);
    if (!providers.isEnabled(providerId)) {
      throw StateError('Source is disabled: ' + providerId);
    }
    return selected;
  }

  WorkCandidate _selectListing(
    CatalogEntry entry, {
    String? providerId,
    required ProviderCapability capability,
  }) {
    for (final listing in entry.listings) {
      if (providerId != null && listing.providerId != providerId) continue;
      final provider = providers.all.where((item) => item.descriptor.id == listing.providerId);
      if (provider.isEmpty || !provider.first.descriptor.supports(capability)) continue;
      if (!providers.isEnabled(listing.providerId)) continue;
      if (capability == ProviderCapability.chapters && provider.first is ChapterFeedProvider) {
        return listing;
      }
    }
    if (providerId != null) {
      throw StateError('The work has no enabled chapter-capable listing for source: ' + providerId);
    }
    throw StateError('The work has no enabled source that supports chapter feeds.');
  }

  ChapterListing _selectChapterListing(ChapterUnit chapter, {String? providerId}) {
    for (final listing in chapter.listings) {
      if (providerId != null && listing.providerId != providerId) continue;
      final provider = providers.all.where((item) => item.descriptor.id == listing.providerId);
      if (provider.isEmpty || !providers.isEnabled(listing.providerId)) continue;
      if (provider.first is ReaderPagesProvider &&
          provider.first.descriptor.supports(ProviderCapability.pages)) {
        return listing;
      }
    }
    throw StateError('The chapter has no enabled source that supports reader pages.');
  }

  T _requireUsable<T>(ProviderResponse<T> response, String operation) {
    if (!response.hasUsableData || response.data == null) {
      throw ReadingJourneyException(
        operation + ' is unavailable (' + response.status.name + '). ' +
            (response.message ?? 'The source returned no usable data.'),
      );
    }
    return response.data as T;
  }

  List<ChapterUnit> _requireUsableList(
    ProviderResponse<List<ChapterUnit>> response,
    String operation,
  ) {
    return _requireUsable(response, operation);
  }

  Future<String> _getDeviceId() async {
    if (_resolvedDeviceId != null) return _resolvedDeviceId!;
    final fromProvider = _deviceIdProvider;
    final candidate = fromProvider == null ? 'local-device' : await fromProvider();
    if (candidate.trim().isEmpty) {
      throw StateError('The configured device identifier is blank.');
    }
    _resolvedDeviceId = candidate;
    return candidate;
  }

  static CatalogEntry? _entryForListing(Iterable<CatalogEntry> catalog, String key) {
    for (final entry in catalog) {
      if (entry.listings.any((listing) => listing.listingKey == key)) return entry;
    }
    return null;
  }

  static String _editionId({
    required String workId,
    required String providerId,
    required String seriesExternalId,
    required String language,
  }) =>
      _stableId('edition', workId + '|' + providerId + '|' + seriesExternalId + '|' + language);

  static String _stableId(String prefix, String value) =>
      prefix + '/' + sha256.convert(utf8.encode(value)).toString();

  Future<T> _serializeCatalogWrite<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _catalogWriteQueue = _catalogWriteQueue.then((_) async {
      try {
        _ensureActive();
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _ensureActive() {
    if (_disposed) throw StateError('Reading journey service is disposed.');
  }

  void dispose() => _disposed = true;
}
