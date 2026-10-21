import 'dart:collection';

import 'models.dart';
import 'identity_matcher.dart';

enum ChapterKind { regular, special, miniChapter, oneShot, volumeExtra }
enum CreatorRole { author, artist, translator, editor, letterer, other }

class EditionRecord {
  EditionRecord({
    required this.id,
    required this.workId,
    required this.format,
    this.title,
    this.languageCode,
    this.releaseYear,
    this.isOfficial = false,
  }) {
    if (id.trim().isEmpty || workId.trim().isEmpty) {
      throw ArgumentError('Edition requires stable edition and work ids.');
    }
    if (languageCode != null && languageCode!.trim().isEmpty) {
      throw ArgumentError.value(languageCode, 'languageCode');
    }
  }

  final String id;
  final String workId;
  final String? title;
  final String? languageCode;
  final int? releaseYear;
  final WorkFormat format;
  final bool isOfficial;
}

class ChapterListing {
  ChapterListing({
    required this.providerId,
    required this.externalId,
    required this.url,
    this.languageCode,
    this.releaseGroup,
    this.publishedAt,
    this.isOfficialTranslation = false,
  }) {
    if (providerId.trim().isEmpty || externalId.trim().isEmpty) {
      throw ArgumentError('Chapter listing requires providerId and externalId.');
    }
    if (!url.isAbsolute || url.host.isEmpty) {
      throw ArgumentError.value(url, 'url', 'Must be an absolute URL');
    }
  }

  final String providerId;
  final String externalId;
  final Uri url;
  final String? languageCode;
  final String? releaseGroup;
  final DateTime? publishedAt;
  final bool isOfficialTranslation;

  String get key => '$providerId:$externalId';
}

class ChapterUnit {
  ChapterUnit({
    required this.id,
    required this.editionId,
    required this.kind,
    required List<ChapterListing> listings,
    this.title,
    this.chapterNumber,
    this.volumeNumber,
    this.miniGroupId,
    this.miniIndex,
    this.miniCount,
  }) : listings = List.unmodifiable(listings) {
    if (id.trim().isEmpty || editionId.trim().isEmpty) {
      throw ArgumentError('Chapter requires stable chapter and edition ids.');
    }
    if (kind == ChapterKind.miniChapter && (miniGroupId == null || miniGroupId!.trim().isEmpty)) {
      throw ArgumentError('Mini-chapters require an explicit miniGroupId to be grouped safely.');
    }
    if (miniIndex != null && miniIndex! < 1) {
      throw ArgumentError.value(miniIndex, 'miniIndex');
    }
    if (miniCount != null && miniCount! < 1) {
      throw ArgumentError.value(miniCount, 'miniCount');
    }
  }

  final String id;
  final String editionId;
  final String? title;
  final double? chapterNumber;
  final int? volumeNumber;
  final ChapterKind kind;
  final String? miniGroupId;
  final int? miniIndex;
  final int? miniCount;
  final List<ChapterListing> listings;

  DateTime? get latestReleaseDate {
    DateTime? latest;
    for (final listing in listings) {
      final date = listing.publishedAt;
      if (date != null && (latest == null || date.isAfter(latest))) latest = date;
    }
    return latest;
  }

  List<ChapterListing> get translations {
    final byLanguage = <String, ChapterListing>{};
    for (final listing in listings) {
      final key = (listing.languageCode ?? 'und').toLowerCase();
      final prior = byLanguage[key];
      if (prior == null || _isNewer(listing, prior)) byLanguage[key] = listing;
    }
    return List.unmodifiable(byLanguage.values);
  }

  static bool _isNewer(ChapterListing next, ChapterListing prior) {
    if (next.publishedAt == null) return false;
    if (prior.publishedAt == null) return true;
    return next.publishedAt!.isAfter(prior.publishedAt!);
  }
}

/// A display-only grouping of equivalent chapter observations from different
/// source editions. The underlying ChapterUnit records remain separate so each
/// tap preserves its own edition, source ID, reading progress, and navigation.
class UnifiedChapterGroup {
  UnifiedChapterGroup({required this.id, required List<ChapterUnit> chapters})
      : chapters = List.unmodifiable(chapters) {
    if (chapters.isEmpty) throw ArgumentError('A unified chapter group cannot be empty.');
  }

  final String id;
  final List<ChapterUnit> chapters;

  ChapterUnit get representative => chapters.first;
  List<String> get providerIds => List.unmodifiable(
        chapters.expand((chapter) => chapter.listings.map((listing) => listing.providerId)).toSet(),
      );
}

/// Groups source-specific chapter rows for presentation only. It deliberately
/// never creates a synthetic ChapterUnit or crosses editions when opening a
/// chapter; the UI must let the reader open one of the original variants.
class UnifiedChapterGrouping {
  const UnifiedChapterGrouping();

  List<UnifiedChapterGroup> group(Iterable<ChapterUnit> chapters) {
    final buckets = LinkedHashMap<String, List<ChapterUnit>>();
    for (final chapter in chapters) {
      final listing = chapter.listings.isEmpty ? null : chapter.listings.first;
      final language = listing?.languageCode?.trim().toLowerCase();
      // Unknown-language rows are not safe to merge across providers.
      final languageKey = language == null || language.isEmpty
          ? 'und:${listing?.providerId ?? chapter.id}'
          : language;
      final volume = chapter.volumeNumber?.toString() ?? '-';
      final number = chapter.chapterNumber;
      final mini = chapter.kind == ChapterKind.miniChapter
          ? ':mini:${chapter.miniIndex ?? 0}'
          : '';
      final String identity;
      if (number != null) {
        identity = '$languageKey:${chapter.kind}:vol:$volume:num:$number$mini';
      } else {
        final title = WorkIdentityMatcher.normalizeTitle(chapter.title ?? '');
        if (title.isEmpty) {
          identity = 'distinct:${chapter.id}';
        } else {
          identity = '$languageKey:${chapter.kind}:vol:$volume:title:$title$mini';
        }
      }
      (buckets[identity] ??= <ChapterUnit>[]).add(chapter);
    }

    final groups = buckets.entries.map((entry) {
      final variants = entry.value.toList()
        ..sort((left, right) {
          final a = left.listings.isEmpty ? '' : left.listings.first.providerId;
          final b = right.listings.isEmpty ? '' : right.listings.first.providerId;
          return a.compareTo(b);
        });
      return UnifiedChapterGroup(id: entry.key, chapters: variants);
    }).toList();

    groups.sort((left, right) {
      final a = left.representative.chapterNumber;
      final b = right.representative.chapterNumber;
      if (a == null && b != null) return -1;
      if (a != null && b == null) return 1;
      if (a != null && b != null && a != b) return b.compareTo(a);
      return left.id.compareTo(right.id);
    });
    return List.unmodifiable(groups);
  }
}

class ChapterGroup {
  ChapterGroup({required this.id, required List<ChapterUnit> units}) : units = List.unmodifiable(units);

  final String id;
  final List<ChapterUnit> units;

  bool get isMiniChapterGroup =>
      units.isNotEmpty && units.every((unit) => unit.kind == ChapterKind.miniChapter);

  String get displayTitle {
    if (!isMiniChapterGroup) {
      final unit = units.first;
      final number = unit.chapterNumber;
      final numberText = number == null
          ? null
          : (number == number.roundToDouble() ? number.toInt().toString() : number.toString());
      return unit.title ?? (numberText == null ? 'Special' : 'Chapter $numberText');
    }
    final first = units.first;
    final number = first.chapterNumber;
    final numberText = number == null
        ? null
        : (number == number.roundToDouble() ? number.toInt().toString() : number.toString());
    final base = numberText == null ? 'Mini-chapters' : 'Chapter $numberText';
    final count = first.miniCount ?? units.length;
    return '$base · $count mini-chapters';
  }
}

/// Groups only explicit mini-chapter families. Unrelated regular chapters are
/// never collapsed based on matching titles or nearby chapter numbers.
class ChapterGrouping {
  const ChapterGrouping();

  List<ChapterGroup> group(Iterable<ChapterUnit> chapters) {
    final buckets = LinkedHashMap<String, List<ChapterUnit>>();
    for (final chapter in chapters) {
      final key = chapter.kind == ChapterKind.miniChapter
          ? 'mini:${chapter.editionId}:${chapter.miniGroupId}'
          : 'unit:${chapter.editionId}:${chapter.id}';
      (buckets[key] ??= <ChapterUnit>[]).add(chapter);
    }

    final groups = buckets.entries.map((entry) {
      final units = entry.value..sort((a, b) => (a.miniIndex ?? 0).compareTo(b.miniIndex ?? 0));
      return ChapterGroup(id: entry.key, units: units);
    }).toList();

    groups.sort((a, b) {
      final aNumber = a.units.first.chapterNumber;
      final bNumber = b.units.first.chapterNumber;
      if (aNumber == null && bNumber != null) return 1;
      if (aNumber != null && bNumber == null) return -1;
      if (aNumber != null && bNumber != null && aNumber != bNumber) {
        return aNumber.compareTo(bNumber);
      }
      return a.id.compareTo(b.id);
    });
    return List.unmodifiable(groups);
  }
}

class CreatorCredit {
  const CreatorCredit({
    required this.workId,
    required this.role,
    this.editionId,
    this.providerId,
  });

  final String workId;
  final String? editionId;
  final CreatorRole role;
  final String? providerId;
}

class CreatorProfile {
  CreatorProfile({
    required this.id,
    required this.name,
    List<String> aliases = const [],
    List<CreatorCredit> credits = const [],
  })  : aliases = List.unmodifiable(aliases),
        credits = List.unmodifiable(credits) {
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw ArgumentError('Creator profile requires stable id and display name.');
    }
  }

  final String id;
  final String name;
  final List<String> aliases;
  final List<CreatorCredit> credits;
}


/// A fresh MangaDex chapter-page manifest. At-home URLs are temporary and
/// must be requested again rather than persisted as permanent media URLs.
class ReaderPageManifest {
  ReaderPageManifest({
    required this.chapterId,
    required this.baseUrl,
    required this.hash,
    required List<String> normalFilenames,
    required List<String> dataSaverFilenames,
  })  : normalFilenames = List.unmodifiable(normalFilenames),
        dataSaverFilenames = List.unmodifiable(dataSaverFilenames) {
    if (chapterId.trim().isEmpty || hash.trim().isEmpty) {
      throw ArgumentError('Page manifest requires a chapter id and hash.');
    }
    if (!baseUrl.isAbsolute ||
        baseUrl.scheme != 'https' ||
        baseUrl.host.isEmpty ||
        baseUrl.userInfo.isNotEmpty ||
        (baseUrl.hasPort && baseUrl.port != 443) ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'Must be a clean public HTTPS URL');
    }
    final backslash = String.fromCharCode(92);
    if (baseUrl.pathSegments.any((segment) =>
        segment == '.' ||
        segment == '..' ||
        segment.contains('/') ||
        segment.contains(backslash))) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'Base URL path contains an unsafe segment');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(hash)) {
      throw ArgumentError.value(hash, 'hash', 'Must be a safe URL path token');
    }
    if (normalFilenames.isEmpty) throw ArgumentError('Page manifest contains no readable pages.');
    if (normalFilenames.any(_unsafeFilename) || dataSaverFilenames.any(_unsafeFilename)) {
      throw ArgumentError('Page filenames must be plain, relative filename segments.');
    }
  }

  final String chapterId;
  final Uri baseUrl;
  final String hash;
  final List<String> normalFilenames;
  final List<String> dataSaverFilenames;

  List<Uri> urls({bool dataSaver = false}) {
    final filenames = dataSaver && dataSaverFilenames.isNotEmpty
        ? dataSaverFilenames
        : normalFilenames;
    final mode = identical(filenames, dataSaverFilenames) ? 'data-saver' : 'data';
    return List.unmodifiable(filenames.map(
      (filename) => baseUrl.replace(
        path: '${baseUrl.path.replaceFirst(RegExp(r'/+$'), '')}/$mode/$hash/${Uri.encodeComponent(filename)}',
        query: null,
        fragment: null,
      ),
    ));
  }

  static bool _unsafeFilename(String value) =>
      value.trim().isEmpty ||
      value == '.' ||
      value == '..' ||
      value.contains('/') ||
      value.contains(String.fromCharCode(92)) ||
      value.contains('\u0000');
}
