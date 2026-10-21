import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

void main() {
  final date = DateTime.utc(2026, 1, 1);
  ChapterUnit mini(String id, int index, DateTime release) => ChapterUnit(
        id: id,
        editionId: 'edition',
        kind: ChapterKind.miniChapter,
        chapterNumber: 12,
        miniGroupId: 'chapter-12-batch',
        miniIndex: index,
        miniCount: 6,
        listings: [
          ChapterListing(
            providerId: 'scan-team',
            externalId: id,
            url: Uri.parse('https://source.example.org/$id'),
            languageCode: 'en',
            publishedAt: release,
          ),
        ],
      );

  ChapterUnit release({
    required String id,
    required String editionId,
    required String providerId,
    required String language,
    required double number,
    String title = 'Chapter',
  }) => ChapterUnit(
        id: id,
        editionId: editionId,
        kind: ChapterKind.regular,
        chapterNumber: number,
        title: title,
        listings: [
          ChapterListing(
            providerId: providerId,
            externalId: id,
            url: Uri.parse('https://$providerId.example.org/$id'),
            languageCode: language,
          ),
        ],
      );

  test('unified chapter grouping keeps source editions separate for reading', () {
    final first = release(
      id: 'a-1', editionId: 'edition-a', providerId: 'source-a',
      language: 'en', number: 1, title: 'The Beginning',
    );
    final second = release(
      id: 'b-1', editionId: 'edition-b', providerId: 'source-b',
      language: 'en', number: 1, title: 'The Start',
    );
    final groups = const UnifiedChapterGrouping().group([first, second]);

    expect(groups, hasLength(1));
    expect(groups.single.chapters, hasLength(2));
    expect(groups.single.chapters.map((chapter) => chapter.editionId),
        containsAll(['edition-a', 'edition-b']));
    expect(groups.single.chapters.map((chapter) => chapter.listings.single.providerId),
        containsAll(['source-a', 'source-b']));
  });

  test('unified chapter grouping does not combine different languages or numbers', () {
    final english = release(
      id: 'en-1', editionId: 'en-edition', providerId: 'source-a',
      language: 'en', number: 1,
    );
    final spanish = release(
      id: 'es-1', editionId: 'es-edition', providerId: 'source-b',
      language: 'es', number: 1,
    );
    final next = release(
      id: 'en-2', editionId: 'en-edition', providerId: 'source-a',
      language: 'en', number: 2,
    );

    expect(const UnifiedChapterGrouping().group([english, spanish, next]), hasLength(3));
  });

  test('shows a grouped mini-chapter count rather than six full chapters', () {
    const grouping = ChapterGrouping();
    final groups = grouping.group([
      mini('m1', 1, date),
      mini('m2', 2, date),
      mini('m3', 3, date),
      mini('m4', 4, date),
      mini('m5', 5, date),
      mini('m6', 6, date),
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.units, hasLength(6));
    expect(groups.single.displayTitle, 'Chapter 12 · 6 mini-chapters');
  });

  test('exposes only the newest listing per translation language', () {
    final chapter = ChapterUnit(
      id: 'chapter-1',
      editionId: 'edition',
      kind: ChapterKind.regular,
      listings: [
        ChapterListing(
          providerId: 'old',
          externalId: '1',
          url: Uri.parse('https://old.example.org/1'),
          languageCode: 'en',
          publishedAt: date,
        ),
        ChapterListing(
          providerId: 'new',
          externalId: '1-new',
          url: Uri.parse('https://new.example.org/1'),
          languageCode: 'en',
          publishedAt: date.add(const Duration(days: 1)),
        ),
      ],
    );
    expect(chapter.translations.single.providerId, 'new');
  });
}
