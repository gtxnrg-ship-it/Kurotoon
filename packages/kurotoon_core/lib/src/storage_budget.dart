enum CacheBucket { providerResponse, cover, page, audio, voiceModel, other }

class CacheEntry {
  const CacheEntry({
    required this.key,
    required this.bucket,
    required this.bytes,
    required this.lastAccessedAt,
    this.pinned = false,
  });

  final String key;
  final CacheBucket bucket;
  final int bytes;
  final DateTime lastAccessedAt;
  final bool pinned;
}

class StoragePlan {
  const StoragePlan({
    required this.accepted,
    required this.evictKeys,
    required this.projectedBytes,
    required this.reason,
  });

  final bool accepted;
  final List<String> evictKeys;
  final int projectedBytes;
  final String reason;
}

class StorageBudget {
  StorageBudget({this.maxBytes = 1610612736}) {
    if (maxBytes < 1) throw ArgumentError.value(maxBytes, 'maxBytes');
  }

  /// Defaults to 1.5 GiB for transient/cache-managed assets, not user-owned data.
  final int maxBytes;

  StoragePlan plan({
    required Iterable<CacheEntry> currentEntries,
    required int incomingBytes,
  }) {
    final entries = currentEntries.toList(growable: false);
    if (incomingBytes < 0 || entries.any((entry) => entry.bytes < 0)) {
      throw ArgumentError('Byte counts cannot be negative');
    }
    if (incomingBytes > maxBytes) {
      return StoragePlan(
        accepted: false,
        evictKeys: const [],
        projectedBytes: entries.fold(0, (sum, item) => sum + item.bytes),
        reason: 'The requested item exceeds the entire cache budget',
      );
    }

    final total = entries.fold<int>(0, (sum, entry) => sum + entry.bytes);
    var projected = total + incomingBytes;
    if (projected <= maxBytes) {
      return StoragePlan(
        accepted: true,
        evictKeys: const [],
        projectedBytes: projected,
        reason: 'Within cache budget',
      );
    }

    final candidates = entries.where((entry) => !entry.pinned).toList()
      ..sort((a, b) {
        final priority = _evictionPriority(a.bucket).compareTo(_evictionPriority(b.bucket));
        return priority != 0 ? priority : a.lastAccessedAt.compareTo(b.lastAccessedAt);
      });
    final evict = <String>[];
    for (final entry in candidates) {
      if (projected <= maxBytes) break;
      projected -= entry.bytes;
      evict.add(entry.key);
    }

    if (projected > maxBytes) {
      return StoragePlan(
        accepted: false,
        evictKeys: List.unmodifiable(evict),
        projectedBytes: projected,
        reason: 'Pinned/offline data prevents safe eviction within the configured budget',
      );
    }
    return StoragePlan(
      accepted: true,
      evictKeys: List.unmodifiable(evict),
      projectedBytes: projected,
      reason: 'Evict least valuable unpinned cache entries before writing',
    );
  }

  int _evictionPriority(CacheBucket bucket) => switch (bucket) {
        CacheBucket.providerResponse => 0,
        CacheBucket.cover => 1,
        CacheBucket.page => 2,
        CacheBucket.audio => 3,
        CacheBucket.other => 4,
        CacheBucket.voiceModel => 5,
      };
}
