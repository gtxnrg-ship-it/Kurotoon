import 'identity_matcher.dart';
import 'models.dart';

enum CatalogUpsertStatus { created, linked, alreadyKnown, reviewRequired }

class CatalogEntry {
  CatalogEntry({
    required this.work,
    required List<WorkCandidate> listings,
    this.verified = false,
  }) : listings = List.unmodifiable(listings);

  final WorkRecord work;
  final List<WorkCandidate> listings;
  final bool verified;

  List<String> get providerIds => List.unmodifiable(listings.map((item) => item.providerId).toSet());
}

class PendingIdentityReview {
  PendingIdentityReview({
    required this.key,
    required this.candidate,
    required List<IdentityDecision> possibleMatches,
  }) : possibleMatches = List.unmodifiable(possibleMatches);

  final String key;
  final WorkCandidate candidate;
  final List<IdentityDecision> possibleMatches;
}

class CatalogUpsertResult {
  const CatalogUpsertResult({
    required this.status,
    this.entry,
    this.review,
    this.message,
  });

  final CatalogUpsertStatus status;
  final CatalogEntry? entry;
  final PendingIdentityReview? review;
  final String? message;
}

class CatalogIndex {
  CatalogIndex({WorkIdentityMatcher matcher = const WorkIdentityMatcher()}) : _matcher = matcher;

  /// Rehydrates a persisted catalog before new provider results are indexed.
  ///
  /// Entries are restored first so their listing identities always win over
  /// stale review-queue records left behind by an interrupted persistence step.
  factory CatalogIndex.fromEntries({
    WorkIdentityMatcher matcher = const WorkIdentityMatcher(),
    Iterable<CatalogEntry> entries = const <CatalogEntry>[],
    Iterable<PendingIdentityReview> pendingReviews = const <PendingIdentityReview>[],
  }) {
    final index = CatalogIndex(matcher: matcher);
    for (final entry in entries) {
      index.restoreEntry(entry);
    }
    for (final review in pendingReviews) {
      // Crash recovery: a listing that has already been committed to the
      // catalog must not reappear as a pending duplicate review.
      if (!index._listingToWork.containsKey(review.key)) {
        index.restorePendingReview(review);
      }
    }
    return index;
  }

  final WorkIdentityMatcher _matcher;

  /// Restores an already-persisted catalog entry without re-running identity
  /// matching. Conflicting stable IDs or provider listing keys are rejected.
  void restoreEntry(CatalogEntry entry) {
    if (_works.containsKey(entry.work.id)) {
      throw StateError('Catalog work is already restored: ${entry.work.id}');
    }
    final keys = <String>{};
    for (final listing in entry.listings) {
      final key = listing.listingKey;
      if (!keys.add(key) || _listingToWork.containsKey(key) || _pending.containsKey(key)) {
        throw StateError('Provider listing identity is already assigned: $key');
      }
    }
    _works[entry.work.id] = entry;
    for (final key in keys) {
      _listingToWork[key] = entry.work.id;
    }
  }

  /// Restores a persisted review only if its identity remains unassigned.
  void restorePendingReview(PendingIdentityReview review) {
    if (review.key != review.candidate.listingKey) {
      throw StateError('Pending review key does not match its provider listing.');
    }
    if (_listingToWork.containsKey(review.key)) {
      throw StateError('A catalog listing cannot also be pending review: ${review.key}');
    }
    if (_pending.containsKey(review.key)) {
      throw StateError('Pending identity review is already restored: ${review.key}');
    }
    _pending[review.key] = review;
  }
  final Map<String, CatalogEntry> _works = {};
  final Map<String, String> _listingToWork = {};
  final Map<String, PendingIdentityReview> _pending = {};

  List<CatalogEntry> get works => List.unmodifiable(_works.values);
  List<PendingIdentityReview> get pendingReviews => List.unmodifiable(_pending.values);
  CatalogEntry? getById(String workId) => _works[workId];
  String? workIdForListing(String listingKey) => _listingToWork[listingKey];

  CatalogUpsertResult upsert(WorkCandidate candidate) {
    final key = candidate.listingKey;
    final knownWorkId = _listingToWork[key];
    if (knownWorkId != null) {
      return CatalogUpsertResult(
        status: CatalogUpsertStatus.alreadyKnown,
        entry: _works[knownWorkId],
        message: 'This provider listing is already in the catalog',
      );
    }
    if (_pending.containsKey(key)) {
      return CatalogUpsertResult(
        status: CatalogUpsertStatus.alreadyKnown,
        review: _pending[key],
        message: 'This listing is already awaiting identity review',
      );
    }

    final safeMatches = <CatalogEntry>[];
    final reviewMatches = <IdentityDecision>[];
    for (final entry in _works.values) {
      final decision = _matcher.compare(entry.work, candidate);
      if (decision.verdict == IdentityVerdict.safeMatch) {
        safeMatches.add(entry);
      } else if (decision.verdict == IdentityVerdict.needsReview) {
        reviewMatches.add(decision);
      }
    }

    if (safeMatches.length == 1 && reviewMatches.isEmpty) {
      final linked = _appendListing(safeMatches.single, candidate);
      return CatalogUpsertResult(status: CatalogUpsertStatus.linked, entry: linked);
    }
    if (safeMatches.length > 1 || reviewMatches.isNotEmpty) {
      final review = PendingIdentityReview(
        key: key,
        candidate: candidate,
        possibleMatches: [
          ...safeMatches.map((entry) => _matcher.compare(entry.work, candidate)),
          ...reviewMatches,
        ],
      );
      _pending[key] = review;
      return CatalogUpsertResult(
        status: CatalogUpsertStatus.reviewRequired,
        review: review,
        message: 'Potential duplicate retained for review; no automatic merge was performed',
      );
    }

    return CatalogUpsertResult(status: CatalogUpsertStatus.created, entry: _createWork(candidate));
  }

  /// Refreshes one existing provider listing without changing the canonical
  /// work identity or accidentally merging it with a different series.
  CatalogEntry refreshKnownListing(WorkCandidate candidate) {
    final workId = _listingToWork[candidate.listingKey];
    if (workId == null) {
      throw ArgumentError.value(candidate.listingKey, 'candidate', 'Provider listing is not in the catalog.');
    }
    final current = _works[workId];
    if (current == null) throw StateError('Catalog listing points to a missing work.');

    final aliases = <String>{...current.work.alternateTitles};
    if (WorkIdentityMatcher.normalizeTitle(candidate.title) !=
        WorkIdentityMatcher.normalizeTitle(current.work.title)) {
      aliases.add(candidate.title);
    }
    aliases.addAll(candidate.alternateTitles);
    final creators = <String>{...current.work.creatorNames, ...candidate.creatorNames};
    final listings = current.listings
        .map((listing) => listing.listingKey == candidate.listingKey ? candidate : listing)
        .toList(growable: false);
    final refreshed = CatalogEntry(
      work: WorkRecord(
        id: current.work.id,
        title: current.work.title,
        alternateTitles: aliases.toList(growable: false),
        creatorNames: creators.toList(growable: false),
        year: current.work.year ?? candidate.year,
        format: current.work.format == WorkFormat.unknown ? candidate.format : current.work.format,
        lockedDistinctIdentity: current.work.lockedDistinctIdentity,
      ),
      listings: listings,
      verified: current.verified,
    );
    _works[workId] = refreshed;
    return refreshed;
  }

  /// Explicitly resolve a candidate. Pass [targetWorkId] to link it to a work,
  /// or [createAsDistinctWork] to affirm that it deserves a separate identity.
  CatalogUpsertResult resolveReview(
    String listingKey, {
    String? targetWorkId,
    bool createAsDistinctWork = false,
  }) {
    final pending = _pending[listingKey];
    if (pending == null) throw ArgumentError.value(listingKey, 'listingKey', 'No pending review');
    if ((targetWorkId == null) == !createAsDistinctWork) {
      throw ArgumentError('Choose exactly one of targetWorkId or createAsDistinctWork.');
    }

    if (targetWorkId != null) {
      final target = _works[targetWorkId];
      if (target == null) throw ArgumentError.value(targetWorkId, 'targetWorkId', 'Unknown work');
      _pending.remove(listingKey);
      final linked = _appendListing(target, pending.candidate);
      return CatalogUpsertResult(status: CatalogUpsertStatus.linked, entry: linked);
    }

    _pending.remove(listingKey);
    final created = _createWork(pending.candidate);
    return CatalogUpsertResult(status: CatalogUpsertStatus.created, entry: created);
  }

  CatalogEntry _createWork(WorkCandidate candidate) {
    final id = 'work/${candidate.listingKey}';
    final work = WorkRecord(
      id: id,
      title: candidate.title,
      alternateTitles: candidate.alternateTitles,
      creatorNames: candidate.creatorNames,
      year: candidate.year,
      format: candidate.format,
    );
    final entry = CatalogEntry(work: work, listings: [candidate]);
    _works[id] = entry;
    _listingToWork[candidate.listingKey] = id;
    return entry;
  }

  CatalogEntry _appendListing(CatalogEntry existing, WorkCandidate candidate) {
    final aliases = <String>{...existing.work.alternateTitles};
    if (WorkIdentityMatcher.normalizeTitle(candidate.title) !=
        WorkIdentityMatcher.normalizeTitle(existing.work.title)) {
      aliases.add(candidate.title);
    }
    aliases.addAll(candidate.alternateTitles);
    final creators = <String>{...existing.work.creatorNames, ...candidate.creatorNames};
    final rebuilt = CatalogEntry(
      work: WorkRecord(
        id: existing.work.id,
        title: existing.work.title,
        alternateTitles: aliases.toList(),
        creatorNames: creators.toList(),
        year: existing.work.year ?? candidate.year,
        format: existing.work.format == WorkFormat.unknown ? candidate.format : existing.work.format,
        lockedDistinctIdentity: existing.work.lockedDistinctIdentity,
      ),
      listings: [...existing.listings, candidate],
      verified: existing.verified,
    );
    _works[existing.work.id] = rebuilt;
    _listingToWork[candidate.listingKey] = existing.work.id;
    return rebuilt;
  }
}
