import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

void main() {
  final clock = DateTime.utc(2026, 1, 1);
  final budget = StorageBudget(maxBytes: 100);

  test('evicts unpinned low-priority cache before newer cover content', () {
    final plan = budget.plan(
      currentEntries: [
        CacheEntry(key: 'response', bucket: CacheBucket.providerResponse, bytes: 40, lastAccessedAt: clock),
        CacheEntry(key: 'cover', bucket: CacheBucket.cover, bytes: 40, lastAccessedAt: clock.add(const Duration(days: 1))),
        CacheEntry(key: 'offline', bucket: CacheBucket.page, bytes: 30, pinned: true, lastAccessedAt: clock),
      ],
      incomingBytes: 20,
    );
    expect(plan.accepted, isTrue);
    expect(plan.evictKeys, contains('response'));
    expect(plan.evictKeys, isNot(contains('offline')));
  });

  test('rejects writes that exceed the complete budget', () {
    expect(budget.plan(currentEntries: const [], incomingBytes: 101).accepted, isFalse);
  });

  test('does not evict pinned data even if this prevents the write', () {
    final plan = budget.plan(
      currentEntries: [
        CacheEntry(key: 'pinned', bucket: CacheBucket.page, bytes: 90, pinned: true, lastAccessedAt: clock),
      ],
      incomingBytes: 20,
    );
    expect(plan.accepted, isFalse);
    expect(plan.evictKeys, isEmpty);
  });
}
