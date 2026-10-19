import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:kurotoon_core/kurotoon_core.dart';

import '../storage/kurotoon_database.dart';

enum CatalogAdmission { created, linked, alreadyKnown, reviewRequired, distinctConfirmed }

class CatalogAdmissionResult {
  const CatalogAdmissionResult({
    required this.entry,
    required this.admission,
    this.message,
  });

  final CatalogEntry entry;
  final CatalogAdmission admission;
  final String? message;
}

class PreparedWork {
  const PreparedWork({
    required this.candidate,
    required this.admissionResult,
    required this.edition,
    required this.detailsStatus,
    this.detailsMessage,
  });

  final WorkCandidate candidate;
  final CatalogAdmissionResult admissionResult;
  final EditionRecord edition;
  final ProviderResultStatus detailsStatus;
  final String? detailsMessage;

  CatalogEntry get catalogEntry => admissionResult.entry;
  String get workId => catalogEntry.work.id;
  String get providerId => candidate.providerId;
  String get externalId => candidate.externalId;
}

class ChapterSyncResult {
  const ChapterSyncResult({
    required this.status,
    required this.chapters,
    required this.nextOffset,
    required this.reachedEnd,
    this.message,
  });

  final ProviderResultStatus status;
  final List<ChapterUnit> chapters;
  final int nextOffset;
  final bool reachedEnd;
  final String? message;

  bool get hasUsableData =>
      chapters.isNotEmpty &&
      (status == ProviderResultStatus.success || status == ProviderResultStatus.partial);
}

/// Joins provider operations to durable catalog/library state.
///
/// The service deliberately keeps source IDs and canonical work IDs separate.
/// Possible duplicates are queued for human review instead of being silently
/// merged, and reader page manifests are always fetched fresh because at-home
/// URLs can expire.
class ReadingWorkflowService {
  ReadingWorkflowService({
    required this.database,
    required this.providers,
    this.deviceId,
    this.defaultChapterPageSize = 100,
    this.defaultMaxChapters = 2000,
    this.providerTimeout = const Duration(seconds: 8),
  }) {
    if (defaultChapterPageSize < 1 || defaultChapterPageSize > 500) {
      throw ArgumentError.value(defaultChapterPageSize, 'defaultChapterPageSize');
    }
    if (defaultMaxChapters < 1 || defaultMaxChapters > 10000) {
      throw ArgumentError.value(defaultMaxChapters, 'defaultMaxChapters');
    }
    if (providerTimeout <= Duration.zero) {
      throw ArgumentError.value(providerTimeout, 'providerTimeout');
    }
    if (deviceId != null && deviceId!.trim().isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId');
    }
  }

  final KurotoonDatabase database;
  final ProviderRegistry providers;
  final String? deviceId;
  final int defaultChapterPageSize;
  final int defaultMaxChapters;
  final Duration providerTimeout;
  Future<String>? _deviceIdFuture;

  /// Resolves a persisted possible-duplicate review after an explicit choice.
  ///
  /// Linking merges the catalog provenance and migrates editions, library
  /// membership, creator credits and progress transactionally. Confirming
  /// distinct protects that work against future automatic identity merges.
  Future<CatalogAdmissionResult> resolveIdentityReview(
    String listingKey, {
    String? targetWorkId,
    bool createAsDistinctWork = false,
  }) async {
    if ((targetWorkId == null && !createAsDistinctWork) ||
        (targetWorkId != null && createAsDistinctWork)) {
      throw ArgumentError('Choose exactly one of targetWorkId or createAsDistinctWork.');
    }
    final pending = await database.loadPendingIdentityReviews();
    PendingIdentityReview? review;
    for (final item in pending) {
      if (item.key == listingKey) {
        review = item;
        break;
      }
    }
    if (review == null) throw ArgumentError.value(listingKey, 'listingKey', 'No pending identity review.');

    final catalog = await database.loadCatalog();
    CatalogEntry? sourceEntry;
    for (final entry in catalog) {
      if (entry.listings.any((listing) => listing.listingKey == listingKey)) {
        sourceEntry = entry;
        break;
      }
    }
    if (sourceEntry == null) {
      throw StateError('The reviewed provider listing is missing from the local catalog.');
    }

    if (createAsDistinctWork) {
      await database.resolvePendingIdentityReviewAsDistinct(listingKey);
      final source = sourceEntry.work;
      final locked = CatalogEntry(
        work: WorkRecord(
          id: source.id,
          title: source.title,
          alternateTitles: source.alternateTitles,
          creatorNames: source.creatorNames,
          year: source.year,
          format: source.format,
          lockedDistinctIdentity: true,
        ),
        listings: sourceEntry.listings,
        verified: sourceEntry.verified,
      );
      return CatalogAdmissionResult(
        entry: locked,
        admission: CatalogAdmission.distinctConfirmed,
        message: 'Confirmed as a separate work; this identity is protected from automatic merging.',
      );
    }

    CatalogEntry? targetEntry;
    for (final entry in catalog) {
      if (entry.work.id == targetWorkId) {
        targetEntry = entry;
        break;
      }
    }
    if (targetEntry == null) {
      throw ArgumentError.value(targetWorkId, 'targetWorkId', 'Target work does not exist.');
    }
    if (targetEntry.work.id == sourceEntry.work.id) {
      await database.deletePendingIdentityReview(listingKey);
      return CatalogAdmissionResult(
        entry: targetEntry,
        admission: CatalogAdmission.alreadyKnown,
        message: 'The reviewed listing already belongs to the selected work.',
      );
    }

    final listingByKey = <String, WorkCandidate>{};
    for (final listing in targetEntry.listings) {
      listingByKey[listing.listingKey] = listing;
    }
    for (final listing in sourceEntry.listings) {
      listingByKey[listing.listingKey] = listing;
    }
    final aliases = <String>{
      ...targetEntry.work.alternateTitles,
      ...sourceEntry.work.alternateTitles,
    };
    if (WorkIdentityMatcher.normalizeTitle(sourceEntry.work.title) !=
        WorkIdentityMatcher.normalizeTitle(targetEntry.work.title)) {
      aliases.add(sourceEntry.work.title);
    }
    final creators = <String>{
      ...targetEntry.work.creatorNames,
      ...sourceEntry.work.creatorNames,
    };
    final canonical = targetEntry.work;
    final merged = CatalogEntry(
      work: WorkRecord(
        id: canonical.id,
        title: canonical.title,
        alternateTitles: aliases.toList(growable: false),
        creatorNames: creators.toList(growable: false),
        year: canonical.year ?? sourceEntry.work.year,
        format: canonical.format == WorkFormat.unknown ? sourceEntry.work.format : canonical.format,
        lockedDistinctIdentity: canonical.lockedDistinctIdentity,
      ),
      listings: listingByKey.values.toList(growable: false),
      verified: targetEntry.verified || sourceEntry.verified,
    );
    await database.mergePendingIdentityReview(
      listingKey: listingKey,
      targetWorkId: targetEntry.work.id,
      mergedEntry: merged,
    );
    return CatalogAdmissionResult(
      entry: merged,
      admission: CatalogAdmission.linked,
      message: 'The provider listings and saved reading state were merged into the selected work.',
    );
  }

  SourceProvider? _provider(String id) {
    for (final provider in providers.all) {
      if (provider.descriptor.id == id) return provider;
    }
    return null;
  }

  /// Saves the selected search listing, refreshes its details when supported,
  /// then ensures the requested translation edition exists locally.
  Future<PreparedWork> prepareWork(
    WorkCandidate candidate, {
    String languageCode = 'en',
    CancellationToken? cancellationToken,
  }) async {
    final language = languageCode.trim().toLowerCase();
    if (!RegExp(r'^[a-z]{2,3}(?:-[a-z]{2})?$').hasMatch(language)) {
      throw ArgumentError.value(languageCode, 'languageCode', 'Use a valid language code such as en or pt-br.');
    }
    final token = cancellationToken ?? CancellationToken();
    token.throwIfCancelled();

    var bestCandidate = candidate;
    var detailsStatus = ProviderResultStatus.unsupported;
    String? detailsMessage;
    final provider = _provider(candidate.providerId);
    if (provider == null) {
      detailsStatus = ProviderResultStatus.disabled;
      detailsMessage = 'The source is no longer installed.';
    } else if (!providers.isEnabled(candidate.providerId)) {
      detailsStatus = ProviderResultStatus.disabled;
      detailsMessage = 'This source is disabled in settings.';
    } else if (provider is SeriesProvider && provider.descriptor.supports(ProviderCapability.series)) {
      try {
        final response = await _boundedProviderCall(
          (requestToken) => provider.getSeries(
            candidate.externalId,
            cancellationToken: requestToken,
          ),
          parentToken: token,
        );
        detailsStatus = response.status;
        detailsMessage = response.message;
        final detailCandidate = response.data;
        if (response.hasUsableData && detailCandidate != null) {
          if (detailCandidate.providerId == candidate.providerId &&
              detailCandidate.externalId == candidate.externalId) {
            bestCandidate = detailCandidate;
          } else {
            detailsStatus = ProviderResultStatus.failed;
            detailsMessage = 'The provider returned details for a different listing; the selected identity was preserved.';
          }
        }
      } on OperationCancelled {
        rethrow;
      } on TimeoutException {
        detailsStatus = ProviderResultStatus.timedOut;
        detailsMessage = 'Series details timed out; the search result was retained.';
      } on Object catch (error) {
        detailsStatus = ProviderResultStatus.failed;
        detailsMessage = 'Series details could not be loaded (${error.runtimeType}).';
      }
    } else {
      detailsStatus = ProviderResultStatus.unsupported;
      detailsMessage = 'This source provides search results but no series-detail endpoint.';
    }

    // Keep the original search result if detail refresh failed; users can still
    // save the result and revisit it when the source is healthy.
    final admission = await _admitCandidate(bestCandidate);
    final edition = EditionRecord(
      id: _editionId(candidate.providerId, candidate.externalId, language),
      workId: admission.entry.work.id,
      title: language.toUpperCase(),
      languageCode: language,
      releaseYear: admission.entry.work.year,
      format: admission.entry.work.format,
    );
    await database.upsertEdition(edition);

    return PreparedWork(
      candidate: bestCandidate,
      admissionResult: admission,
      edition: edition,
      detailsStatus: detailsStatus,
      detailsMessage: detailsMessage,
    );
  }

  /// Persists a candidate using conservative cross-source identity matching.
  /// The review-needed candidate remains independently readable until a person
  /// confirms whether it belongs to an existing work.
  Future<CatalogAdmissionResult> _admitCandidate(WorkCandidate candidate) async {
    final catalog = await database.loadCatalog();
    for (final entry in catalog) {
      final listingIndex = entry.listings.indexWhere((item) => item.listingKey == candidate.listingKey);
      if (listingIndex < 0) continue;
      final listings = [...entry.listings.where((item) => item.listingKey != candidate.listingKey), candidate];
      final updated = _refreshWorkMetadata(entry, candidate, listings);
      await database.upsertCatalogEntry(updated);
      return CatalogAdmissionResult(
        entry: updated,
        admission: CatalogAdmission.alreadyKnown,
        message: 'This exact source listing was already in the catalog.',
      );
    }

    const matcher = WorkIdentityMatcher();
    final safeMatches = <CatalogEntry>[];
    final possibleReviews = <IdentityDecision>[];
    for (final entry in catalog) {
      final decision = matcher.compare(entry.work, candidate);
      if (decision.verdict == IdentityVerdict.safeMatch) {
        safeMatches.add(entry);
      } else if (decision.verdict == IdentityVerdict.needsReview) {
        possibleReviews.add(decision);
      }
    }

    if (safeMatches.length == 1 && possibleReviews.isEmpty) {
      final target = safeMatches.single;
      final updated = _refreshWorkMetadata(target, candidate, [...target.listings, candidate]);
      await database.upsertCatalogEntry(updated);
      return CatalogAdmissionResult(entry: updated, admission: CatalogAdmission.linked);
    }

    if (safeMatches.length > 1 || possibleReviews.isNotEmpty) {
      final review = PendingIdentityReview(
        key: candidate.listingKey,
        candidate: candidate,
        possibleMatches: [
          ...safeMatches.map((entry) => matcher.compare(entry.work, candidate)),
          ...possibleReviews,
        ],
      );
      await database.savePendingIdentityReview(review);
      final isolated = _newCatalogEntry(candidate);
      await database.upsertCatalogEntry(isolated);
      return CatalogAdmissionResult(
        entry: isolated,
        admission: CatalogAdmission.reviewRequired,
        message: 'Possible duplicate saved separately; no source listings were merged.',
      );
    }

    final created = _newCatalogEntry(candidate);
    await database.upsertCatalogEntry(created);
    return CatalogAdmissionResult(entry: created, admission: CatalogAdmission.created);
  }

  CatalogEntry _newCatalogEntry(WorkCandidate candidate) {
    final encodedKey = base64Url.encode(utf8.encode(candidate.listingKey)).replaceAll('=', '');
    return CatalogEntry(
      work: WorkRecord(
        id: 'work/$encodedKey',
        title: candidate.title,
        alternateTitles: candidate.alternateTitles,
        creatorNames: candidate.creatorNames,
        year: candidate.year,
        format: candidate.format,
      ),
      listings: [candidate],
    );
  }

  CatalogEntry _refreshWorkMetadata(
    CatalogEntry existing,
    WorkCandidate candidate,
    List<WorkCandidate> listings,
  ) {
    final aliases = <String>{...existing.work.alternateTitles, ...candidate.alternateTitles};
    if (WorkIdentityMatcher.normalizeTitle(candidate.title) !=
        WorkIdentityMatcher.normalizeTitle(existing.work.title)) {
      aliases.add(candidate.title);
    }
    final creators = <String>{...existing.work.creatorNames, ...candidate.creatorNames};
    return CatalogEntry(
      work: WorkRecord(
        id: existing.work.id,
        title: existing.work.title,
        alternateTitles: aliases.toList(),
        creatorNames: creators.toList(),
        year: existing.work.year ?? candidate.year,
        format: existing.work.format == WorkFormat.unknown ? candidate.format : existing.work.format,
        lockedDistinctIdentity: existing.work.lockedDistinctIdentity,
      ),
      listings: listings,
      verified: existing.verified,
    );
  }

  String _editionId(String providerId, String externalId, String languageCode) =>
      '$providerId:$externalId:$languageCode';

  /// Fetches chapter pages with bounded pagination and durable incremental
  /// writes. No provider is allowed to return an unbounded chapter list.
  Future<ChapterSyncResult> syncChapters(
    PreparedWork work, {
    List<String>? translatedLanguages,
    int? pageSize,
    int? maxChapters,
    int startOffset = 0,
    CancellationToken? cancellationToken,
  }) async {
    final size = pageSize ?? defaultChapterPageSize;
    final ceiling = maxChapters ?? defaultMaxChapters;
    if (size < 1 || size > 500) throw ArgumentError.value(size, 'pageSize');
    if (ceiling < 1 || ceiling > 10000) throw ArgumentError.value(ceiling, 'maxChapters');
    if (startOffset < 0) throw ArgumentError.value(startOffset, 'startOffset');
    final requestedLanguages = translatedLanguages ?? [work.edition.languageCode ?? 'en'];
    final languages = requestedLanguages.map((value) => value.trim().toLowerCase()).toSet().toList();
    if (languages.isEmpty ||
        languages.length > 8 ||
        languages.any((value) => !RegExp(r'^[a-z]{2,3}(?:-[a-z]{2})?$').hasMatch(value))) {
      throw ArgumentError.value(
        requestedLanguages,
        'translatedLanguages',
        'Use between one and eight valid language codes such as en or pt-br.',
      );
    }
    if (languages.length != 1) {
      throw ArgumentError.value(
        requestedLanguages,
        'translatedLanguages',
        'Sync one language per edition; prepare a separate edition for each language.',
      );
    }
    if (work.edition.languageCode != null &&
        languages.single != work.edition.languageCode!.toLowerCase()) {
      throw ArgumentError.value(
        requestedLanguages,
        'translatedLanguages',
        'The requested language does not match the prepared edition.',
      );
    }

    final source = _provider(work.providerId);
    if (source == null || !providers.isEnabled(work.providerId)) {
      return const ChapterSyncResult(
        status: ProviderResultStatus.disabled,
        chapters: [],
        nextOffset: 0,
        reachedEnd: false,
        message: 'The selected source is unavailable or disabled.',
      );
    }
    if (source is! ChapterFeedProvider || !source.descriptor.supports(ProviderCapability.chapters)) {
      return const ChapterSyncResult(
        status: ProviderResultStatus.unsupported,
        chapters: [],
        nextOffset: 0,
        reachedEnd: true,
        message: 'This source does not provide chapter feeds.',
      );
    }

    final token = cancellationToken ?? CancellationToken();
    final all = <String, ChapterUnit>{};
    var offset = startOffset;
    var reachedEnd = false;
    var status = ProviderResultStatus.success;
    String? message;

    while (all.length < ceiling) {
      token.throwIfCancelled();
      ProviderResponse<List<ChapterUnit>> response;
      try {
        response = await _boundedProviderCall(
          (requestToken) => source.getChapters(
            work.externalId,
            cancellationToken: requestToken,
            translatedLanguages: languages,
            limit: size,
            offset: offset,
          ),
          parentToken: token,
        );
      } on OperationCancelled {
        rethrow;
      } on TimeoutException {
        if (all.isEmpty) {
          return ChapterSyncResult(
            status: ProviderResultStatus.timedOut,
            chapters: const [],
            nextOffset: offset,
            reachedEnd: false,
            message: 'Chapter loading timed out; try again when the source is responsive.',
          );
        }
        status = ProviderResultStatus.partial;
        message = 'Chapter loading timed out; previously saved chapters are preserved.';
        break;
      }
      final page = response.data;
      if (!response.hasUsableData || page == null) {
        if (all.isEmpty) {
          return ChapterSyncResult(
            status: response.status,
            chapters: const [],
            nextOffset: offset,
            reachedEnd: false,
            message: response.message ?? 'No chapters were returned by the provider.',
          );
        }
        status = ProviderResultStatus.partial;
        message = response.message ?? 'Chapter loading stopped after a provider error; already saved chapters are preserved.';
        break;
      }
      if (response.status == ProviderResultStatus.partial) {
        status = ProviderResultStatus.partial;
        message = response.message;
      }

      // Treat provider chapter metadata as untrusted. A malformed or buggy
      // source must not write chapters into a different work/edition or make a
      // chapter from another language appear in this edition's reading list.
      String? invalidPageReason;
      for (final chapter in page) {
        if (chapter.editionId != work.edition.id) {
          invalidPageReason = 'The source returned a chapter for a different edition.';
          break;
        }
        if (chapter.listings.isEmpty ||
            chapter.listings.any((listing) => listing.providerId != work.providerId)) {
          invalidPageReason = 'The source returned a chapter with invalid listing provenance.';
          break;
        }
        if (chapter.listings.any((listing) =>
            listing.languageCode != null &&
            listing.languageCode!.trim().toLowerCase() != languages.single)) {
          invalidPageReason = 'The source returned a chapter in a different translation language.';
          break;
        }
      }
      if (invalidPageReason != null) {
        if (all.isEmpty) {
          return ChapterSyncResult(
            status: ProviderResultStatus.failed,
            chapters: const [],
            nextOffset: offset,
            reachedEnd: false,
            message: invalidPageReason,
          );
        }
        status = ProviderResultStatus.partial;
        message = invalidPageReason;
        break;
      }

      var added = 0;
      final editions = <String, EditionRecord>{};
      for (final chapter in page) {
        if (all.containsKey(chapter.id)) continue;
        all[chapter.id] = chapter;
        added++;
        String? listedLanguage;
        for (final listing in chapter.listings) {
          if (listing.languageCode != null) {
            listedLanguage = listing.languageCode;
            break;
          }
        }
        final language = listedLanguage ?? languages.first;
        editions.putIfAbsent(
          chapter.editionId,
          () => EditionRecord(
            id: chapter.editionId,
            workId: work.workId,
            title: language.toUpperCase(),
            languageCode: language,
            releaseYear: work.catalogEntry.work.year,
            format: work.catalogEntry.work.format,
          ),
        );
      }

      if (editions.isEmpty) editions[work.edition.id] = work.edition;
      for (final edition in editions.values) {
        await database.upsertEdition(edition);
      }
      for (final chapter in page) {
        await database.upsertChapter(chapter);
      }

      offset += page.length;
      if (page.length < size) {
        reachedEnd = response.status != ProviderResultStatus.partial;
        break;
      }
      if (added == 0) {
        status = ProviderResultStatus.partial;
        message = 'Pagination stopped because the source repeated an entire page.';
        break;
      }
    }

    if (!reachedEnd && all.length >= ceiling) {
      status = ProviderResultStatus.partial;
      message ??= 'Reached the configured chapter safety limit ($ceiling). Load more from offset $offset to continue.';
    }
    final sorted = all.values.toList()
      ..sort((a, b) {
        final aNumber = a.chapterNumber;
        final bNumber = b.chapterNumber;
        if (aNumber == null && bNumber != null) return 1;
        if (aNumber != null && bNumber == null) return -1;
        if (aNumber != null && bNumber != null && aNumber != bNumber) return aNumber.compareTo(bNumber);
        return a.id.compareTo(b.id);
      });
    return ChapterSyncResult(
      status: status,
      chapters: List.unmodifiable(sorted),
      nextOffset: offset,
      reachedEnd: reachedEnd,
      message: message,
    );
  }

  /// Always fetches a fresh page manifest; temporary at-home URLs are never
  /// written to the catalog database as durable chapter metadata.
  Future<ProviderResponse<ReaderPageManifest>> loadReaderManifest(
    PreparedWork work,
    ChapterUnit chapter, {
    String? preferredProviderId,
    bool dataSaver = false,
    CancellationToken? cancellationToken,
  }) async {
    if (chapter.editionId != work.edition.id) {
      return const ProviderResponse(
        status: ProviderResultStatus.failed,
        message: 'The selected chapter belongs to a different edition.',
      );
    }
    final available = chapter.listings.where((item) =>
      preferredProviderId == null || item.providerId == preferredProviderId
    );
    ChapterListing? listing;
    SourceProvider? source;
    for (final item in available) {
      final candidate = _provider(item.providerId);
      if (candidate != null && providers.isEnabled(item.providerId) &&
          candidate is ReaderPagesProvider &&
          candidate.descriptor.supports(ProviderCapability.pages)) {
        listing = item;
        source = candidate;
        break;
      }
    }
    if (listing == null || source is! ReaderPagesProvider) {
      return const ProviderResponse(
        status: ProviderResultStatus.unsupported,
        message: 'No enabled source can provide readable pages for this chapter.',
      );
    }
    try {
      final response = await _boundedProviderCall(
        (requestToken) => source!.getPages(
          listing!.externalId,
          cancellationToken: requestToken,
          dataSaver: dataSaver,
        ),
        parentToken: cancellationToken,
      );
      final manifest = response.data;
      if (response.hasUsableData && manifest != null && manifest.chapterId != listing.externalId) {
        return const ProviderResponse(
          status: ProviderResultStatus.failed,
          message: 'Reader manifest chapter identity did not match the selected listing.',
        );
      }
      return response;
    } on OperationCancelled catch (error) {
      return ProviderResponse(status: ProviderResultStatus.cancelled, message: error.reason);
    } on TimeoutException {
      return const ProviderResponse(
        status: ProviderResultStatus.timedOut,
        message: 'Reader page loading timed out; request the manifest again to retry.',
      );
    } on Object catch (error) {
      return ProviderResponse(
        status: ProviderResultStatus.failed,
        message: 'Reader page loading failed (${error.runtimeType}).',
      );
    }
  }

  Future<void> addToLibrary(
    PreparedWork work, {
    LibraryStatus status = LibraryStatus.planned,
    int sortOrder = 0,
  }) async {
    final existing = await database.loadLibrary();
    LibraryRecord? prior;
    for (final record in existing) {
      if (record.workId == work.workId && record.editionId == work.edition.id) {
        prior = record;
        break;
      }
    }
    await database.putLibraryRecord(LibraryRecord(
      workId: work.workId,
      editionId: work.edition.id,
      status: status,
      addedAt: prior?.addedAt ?? DateTime.now(),
      sortOrder: prior?.sortOrder ?? sortOrder,
      lastOpenedAt: prior?.lastOpenedAt,
    ));
  }

  Future<ReadingProgress> saveProgress(
    PreparedWork work,
    ChapterUnit chapter, {
    required double fraction,
    String? anchor,
  }) async {
    if (chapter.editionId != work.edition.id) {
      throw ArgumentError('Cannot save progress for a chapter in another edition.');
    }
    final knownChapters = await database.loadChapters(work.edition.id);
    if (!knownChapters.any((item) => item.id == chapter.id)) {
      throw StateError('Cannot save reading progress for a chapter that has not been persisted.');
    }
    final prior = await database.loadProgress(work.workId, work.edition.id);
    final progress = ReadingProgress(
      workId: work.workId,
      editionId: work.edition.id,
      chapterId: chapter.id,
      anchor: anchor,
      fraction: fraction,
      updatedAt: DateTime.now(),
      deviceId: await _localDeviceId(),
      revision: (prior?.revision ?? 0) + 1,
    );
    final saved = await database.saveProgress(progress);
    final library = await database.loadLibrary();
    for (final record in library) {
      if (record.workId == work.workId && record.editionId == work.edition.id) {
        await database.putLibraryRecord(LibraryRecord(
          workId: record.workId,
          editionId: record.editionId,
          status: record.status == LibraryStatus.planned ? LibraryStatus.reading : record.status,
          addedAt: record.addedAt,
          sortOrder: record.sortOrder,
          lastOpenedAt: DateTime.now(),
        ));
        break;
      }
    }
    return saved;
  }

  Future<ReadingProgress?> resumeProgress(PreparedWork work) async {
    final saved = await database.loadProgress(work.workId, work.edition.id);
    if (saved == null) return null;
    final chapters = await database.loadChapters(work.edition.id);
    return chapters.any((chapter) => chapter.id == saved.chapterId) ? saved : null;
  }

  Future<T> _boundedProviderCall<T>(
    Future<T> Function(CancellationToken requestToken) operation, {
    CancellationToken? parentToken,
  }) async {
    parentToken?.throwIfCancelled();
    final requestToken = CancellationToken();
    final detach = parentToken?.onCancel((reason) => requestToken.cancel(reason));
    try {
      return await operation(requestToken).timeout(
        providerTimeout,
        onTimeout: () {
          requestToken.cancel('Provider request timed out');
          throw TimeoutException('Provider request exceeded $providerTimeout');
        },
      );
    } finally {
      detach?.call();
    }
  }

  Future<String> _localDeviceId() {
    final explicit = deviceId;
    if (explicit != null) return Future.value(explicit);
    return _deviceIdFuture ??= () async {
      final saved = await database.getSetting<String>('device.installId');
      if (saved != null && saved.trim().isNotEmpty) return saved;
      final random = Random.secure();
      final created = 'device-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${random.nextInt(1 << 32).toRadixString(36)}';
      await database.setSetting('device.installId', created);
      return created;
    }();
  }
}
