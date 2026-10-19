import 'dart:collection';

import 'models.dart';

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
    required this.listings,
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

class ChapterGroup {
  ChapterGroup({required this.id, required this.units}) : units = List.unmodifiable(units);

  final String id;
  final List<ChapterUnit> units;

  bool get isMiniChapterGroup =>
      units.isNotEmpty && units.every((unit) => unit.kind == ChapterKind.miniChapter);

  String get displayTitle {
    if (!isMiniChapterGroup) {
      final unit = units.first;
      return unit.title ?? (unit.chapterNumber == null ? 'Special' : 'Chapter ${unit.chapterNumber}');
    }
    final first = units.first;
    final base = first.chapterNumber == null ? 'Mini-chapters' : 'Chapter ${first.chapterNumber}';
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
    this.aliases = const [],
    this.credits = const [],
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
