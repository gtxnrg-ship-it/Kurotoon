import 'dart:collection';

enum ProviderCapability {
  search,
  series,
  chapters,
  pages,
  creators,
  comments,
}

enum WorkFormat { manga, manhwa, manhua, webtoon, comic, novel, oneShot, unknown }

enum ProviderResultStatus {
  success,
  partial,
  timedOut,
  rateLimited,
  blocked,
  disabled,
  cancelled,
  unsupported,
  failed,
}

class ProviderDescriptor {
  ProviderDescriptor({
    required this.id,
    required this.name,
    required this.homepage,
    required this.capabilities,
    this.isBuiltIn = false,
    this.enabledByDefault = true,
  }) : capabilities = UnmodifiableSetView(Set<ProviderCapability>.from(capabilities)) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id', 'Must not be blank');
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name', 'Must not be blank');
    if (!homepage.isAbsolute || homepage.host.isEmpty) {
      throw ArgumentError.value(homepage, 'homepage', 'Must be an absolute URL');
    }
  }

  final String id;
  final String name;
  final Uri homepage;
  final Set<ProviderCapability> capabilities;
  final bool isBuiltIn;
  final bool enabledByDefault;

  bool supports(ProviderCapability capability) => capabilities.contains(capability);
}

class ProviderListing {
  ProviderListing({
    required this.providerId,
    required this.externalId,
    required this.url,
    this.language,
    this.releaseDate,
    this.chapterNumber,
    this.isOfficialTranslation = false,
  }) {
    if (providerId.trim().isEmpty || externalId.trim().isEmpty) {
      throw ArgumentError('A provider listing requires providerId and externalId.');
    }
    if (!url.isAbsolute || url.host.isEmpty) {
      throw ArgumentError.value(url, 'url', 'Must be an absolute URL');
    }
  }

  final String providerId;
  final String externalId;
  final Uri url;
  final String? language;
  final DateTime? releaseDate;
  final double? chapterNumber;
  final bool isOfficialTranslation;

  String get key => '$providerId:$externalId';
}

class WorkCandidate {
  WorkCandidate({
    required this.providerId,
    required this.externalId,
    required this.title,
    required this.providerUrl,
    this.alternateTitles = const [],
    this.creatorNames = const [],
    this.year,
    this.format = WorkFormat.unknown,
    this.language,
    this.description,
    this.coverUrl,
    this.tags = const [],
  })  : alternateTitles = List.unmodifiable(alternateTitles),
        creatorNames = List.unmodifiable(creatorNames),
        tags = List.unmodifiable(tags) {
    if (providerId.trim().isEmpty || externalId.trim().isEmpty) {
      throw ArgumentError('A work candidate requires providerId and externalId.');
    }
    if (title.trim().isEmpty) throw ArgumentError.value(title, 'title', 'Must not be blank');
    if (!providerUrl.isAbsolute || providerUrl.host.isEmpty) {
      throw ArgumentError.value(providerUrl, 'providerUrl', 'Must be an absolute URL');
    }
  }

  final String providerId;
  final String externalId;
  final String title;
  final List<String> alternateTitles;
  final List<String> creatorNames;
  final int? year;
  final WorkFormat format;
  final String? language;
  final String? description;
  final Uri? coverUrl;
  final List<String> tags;

  String get listingKey => '$providerId:$externalId';
}

class WorkRecord {
  WorkRecord({
    required this.id,
    required this.title,
    this.alternateTitles = const [],
    this.creatorNames = const [],
    this.year,
    this.format = WorkFormat.unknown,
    this.lockedDistinctIdentity = false,
  })  : alternateTitles = List.unmodifiable(alternateTitles),
        creatorNames = List.unmodifiable(creatorNames) {
    if (id.trim().isEmpty || title.trim().isEmpty) {
      throw ArgumentError('A work requires a stable id and a title.');
    }
  }

  final String id;
  final String title;
  final List<String> alternateTitles;
  final List<String> creatorNames;
  final int? year;
  final WorkFormat format;

  /// When true, automated matching must never merge another listing into this work.
  final bool lockedDistinctIdentity;
}

class ProviderResponse<T> {
  const ProviderResponse({
    required this.status,
    this.data,
    this.message,
    this.retryAfter,
  });

  final ProviderResultStatus status;
  final T? data;
  final String? message;
  final Duration? retryAfter;

  bool get hasUsableData =>
      data != null && (status == ProviderResultStatus.success || status == ProviderResultStatus.partial);
  bool get isTerminalFailure =>
      status == ProviderResultStatus.timedOut ||
      status == ProviderResultStatus.rateLimited ||
      status == ProviderResultStatus.blocked ||
      status == ProviderResultStatus.disabled ||
      status == ProviderResultStatus.cancelled ||
      status == ProviderResultStatus.unsupported ||
      status == ProviderResultStatus.failed;
}
