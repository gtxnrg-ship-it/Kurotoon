import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

WorkCandidate candidate({
  required String provider,
  required String id,
  String title = 'Blue Star',
  List<String> creators = const [],
  int? year,
}) => WorkCandidate(
      providerId: provider,
      externalId: id,
      title: title,
      creatorNames: creators,
      year: year,
      format: WorkFormat.manga,
      providerUrl: Uri.parse('https://$provider.example.org/$id'),
    );

void main() {
  test('retains provider provenance while linking with strong evidence', () {
    final index = CatalogIndex();
    final first = index.upsert(candidate(provider: 'a', id: '1', creators: ['Artist'], year: 2020));
    expect(first.status, CatalogUpsertStatus.created);
    final second = index.upsert(candidate(provider: 'b', id: '2', creators: ['Artist'], year: 2020));
    expect(second.status, CatalogUpsertStatus.linked);
    expect(index.works, hasLength(1));
    expect(second.entry!.providerIds, containsAll(['a', 'b']));
    expect(index.workIdForListing('b:2'), first.entry!.work.id);
  });

  test('holds uncertain title-only match for explicit review', () {
    final index = CatalogIndex();
    index.upsert(candidate(provider: 'a', id: '1'));
    final result = index.upsert(candidate(provider: 'b', id: '2'));
    expect(result.status, CatalogUpsertStatus.reviewRequired);
    expect(index.works, hasLength(1));
    expect(index.pendingReviews, hasLength(1));
  });

  test('can confirm a likely duplicate or confirm a distinct edition', () {
    final index = CatalogIndex();
    final original = index.upsert(candidate(provider: 'a', id: '1'));
    index.upsert(candidate(provider: 'b', id: '2'));
    final linked = index.resolveReview('b:2', targetWorkId: original.entry!.work.id);
    expect(linked.status, CatalogUpsertStatus.linked);
    expect(index.works, hasLength(1));
    expect(index.pendingReviews, isEmpty);
  });

  test('deduplicates a repeated provider listing', () {
    final index = CatalogIndex();
    index.upsert(candidate(provider: 'a', id: '1'));
    final again = index.upsert(candidate(provider: 'a', id: '1'));
    expect(again.status, CatalogUpsertStatus.alreadyKnown);
  });
  test('restores persisted entries before matching new provider listings', () {
    final originalIndex = CatalogIndex();
    final original = originalIndex.upsert(
      candidate(provider: 'a', id: '1', creators: ['Artist'], year: 2020),
    );
    final restored = CatalogIndex.fromEntries(entries: originalIndex.works);

    final linked = restored.upsert(
      candidate(provider: 'b', id: '2', creators: ['Artist'], year: 2020),
    );

    expect(linked.status, CatalogUpsertStatus.linked);
    expect(linked.entry!.work.id, original.entry!.work.id);
    expect(linked.entry!.providerIds, containsAll(['a', 'b']));
    expect(restored.works, hasLength(1));
  });

  test('restores pending reviews and lets a user resolve them after restart', () {
    final firstRun = CatalogIndex();
    final original = firstRun.upsert(candidate(provider: 'a', id: '1'));
    firstRun.upsert(candidate(provider: 'b', id: '2'));
    final restored = CatalogIndex.fromEntries(
      entries: firstRun.works,
      pendingReviews: firstRun.pendingReviews,
    );

    expect(restored.pendingReviews, hasLength(1));
    final result = restored.resolveReview('b:2', targetWorkId: original.entry!.work.id);
    expect(result.status, CatalogUpsertStatus.linked);
    expect(result.entry!.providerIds, containsAll(['a', 'b']));
    expect(restored.pendingReviews, isEmpty);
  });

  test('ignores a stale persisted review if that listing is already catalogued', () {
    final firstRun = CatalogIndex();
    firstRun.upsert(candidate(provider: 'a', id: '1'));
    final reviewRun = CatalogIndex.fromEntries(entries: firstRun.works);
    final pending = reviewRun.upsert(candidate(provider: 'b', id: '2'));
    expect(pending.status, CatalogUpsertStatus.reviewRequired);

    // Simulate the catalog commit succeeding before removal of the old queue row.
    final recovered = CatalogIndex.fromEntries(
      entries: [
        ...firstRun.works,
        CatalogEntry(
          work: WorkRecord(
            id: 'work/b:2',
            title: 'Blue Star',
            alternateTitles: const [],
            creatorNames: const [],
            format: WorkFormat.manga,
          ),
          listings: [candidate(provider: 'b', id: '2')],
        ),
      ],
      pendingReviews: [pending.review!],
    );

    expect(recovered.pendingReviews, isEmpty);
    expect(recovered.upsert(candidate(provider: 'b', id: '2')).status, CatalogUpsertStatus.alreadyKnown);
  });

  test('rejects persisted provider identities assigned to two different works', () {
    final listing = candidate(provider: 'a', id: '1');
    final entries = [
      CatalogEntry(
        work: WorkRecord(id: 'work/one', title: 'One'),
        listings: [listing],
      ),
      CatalogEntry(
        work: WorkRecord(id: 'work/two', title: 'Two'),
        listings: [listing],
      ),
    ];

    expect(() => CatalogIndex.fromEntries(entries: entries), throwsStateError);
  });

  test('refreshes provider metadata while preserving canonical catalog identity', () {
    final index = CatalogIndex();
    final created = index.upsert(
      candidate(provider: 'a', id: '1', creators: ['Artist'], year: 2020),
    );
    final refreshedCandidate = WorkCandidate(
      providerId: 'a',
      externalId: '1',
      title: 'Blue Star: New Edition',
      alternateTitles: const ['The Blue Star'],
      creatorNames: const ['Artist', 'Writer'],
      year: 2021,
      format: WorkFormat.manga,
      providerUrl: Uri.parse('https://a.example.org/1'),
      description: 'Updated synopsis',
    );

    final refreshed = index.refreshKnownListing(refreshedCandidate);

    expect(refreshed.work.id, created.entry!.work.id);
    expect(refreshed.work.title, 'Blue Star');
    expect(refreshed.work.alternateTitles, contains('Blue Star: New Edition'));
    expect(refreshed.work.creatorNames, contains('Writer'));
    expect(refreshed.listings.single.description, 'Updated synopsis');
    expect(index.workIdForListing('a:1'), created.entry!.work.id);
  });

}
