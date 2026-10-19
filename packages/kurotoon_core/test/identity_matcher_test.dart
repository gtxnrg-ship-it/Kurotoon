import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

void main() {
  const matcher = WorkIdentityMatcher();

  test('requires supporting evidence before automatic merge', () {
    final work = WorkRecord(id: 'work-1', title: 'The Blue Star', year: 2020);
    final candidate = WorkCandidate(
      providerId: 'source-a',
      externalId: '11',
      title: 'The Blue Star',
      providerUrl: Uri.parse('https://example.com/series/11'),
    );
    expect(matcher.compare(work, candidate).verdict, IdentityVerdict.needsReview);
  });

  test('same title, creator, year, and format can safely match', () {
    final work = WorkRecord(
      id: 'work-1',
      title: 'Blue Star!',
      creatorNames: const ['A. Artist'],
      year: 2020,
      format: WorkFormat.manhwa,
    );
    final candidate = WorkCandidate(
      providerId: 'source-b',
      externalId: '22',
      title: 'blue star',
      creatorNames: const ['a artist'],
      year: 2020,
      format: WorkFormat.manhwa,
      providerUrl: Uri.parse('https://example.com/series/22'),
    );
    expect(matcher.compare(work, candidate).safeToMerge, isTrue);
  });

  test('contradictory years or formats veto automatic merge', () {
    final work = WorkRecord(
      id: 'work-1',
      title: 'Blue Star',
      year: 2001,
      format: WorkFormat.manga,
    );
    final candidate = WorkCandidate(
      providerId: 'source-b',
      externalId: '22',
      title: 'Blue Star',
      year: 2020,
      format: WorkFormat.manga,
      providerUrl: Uri.parse('https://example.com/series/22'),
    );
    expect(matcher.compare(work, candidate).verdict, IdentityVerdict.distinct);
  });

  test('preserves non-Latin titles and respects locked identities', () {
    expect(WorkIdentityMatcher.normalizeTitle('사랑! と 星'), '사랑 と 星');
    final work = WorkRecord(id: 'work-1', title: 'Blue Star', lockedDistinctIdentity: true);
    final candidate = WorkCandidate(
      providerId: 'source-b',
      externalId: '22',
      title: 'Blue Star',
      providerUrl: Uri.parse('https://example.com/series/22'),
    );
    expect(matcher.compare(work, candidate).verdict, IdentityVerdict.distinct);
  });
}
