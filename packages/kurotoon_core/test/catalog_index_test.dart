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
}
