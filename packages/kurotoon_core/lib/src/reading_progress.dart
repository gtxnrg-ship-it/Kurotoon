class ReadingProgress {
  ReadingProgress({
    required this.workId,
    required this.editionId,
    required this.chapterId,
    required this.updatedAt,
    required this.deviceId,
    this.anchor,
    this.fraction = 0,
    this.revision = 0,
  }) {
    if (workId.trim().isEmpty || editionId.trim().isEmpty || chapterId.trim().isEmpty) {
      throw ArgumentError('Progress requires work, edition, and chapter ids.');
    }
    if (deviceId.trim().isEmpty) throw ArgumentError.value(deviceId, 'deviceId');
    if (!fraction.isFinite || fraction < 0 || fraction > 1) {
      throw ArgumentError.value(fraction, 'fraction', 'Must be finite and between 0 and 1');
    }
    if (revision < 0) throw ArgumentError.value(revision, 'revision');
  }

  final String workId;
  final String editionId;
  final String chapterId;
  final String? anchor;
  final double fraction;
  final DateTime updatedAt;
  final String deviceId;
  final int revision;

  String get key => '$workId:$editionId';
}

/// Last-write-wins by timestamp; revision/device provide deterministic tie breaks.
/// A newer intentional rewind remains valid—the fraction is not forced forward.
ReadingProgress mergeProgress(ReadingProgress? current, ReadingProgress incoming) {
  if (current == null) return incoming;
  final timeOrder = incoming.updatedAt.compareTo(current.updatedAt);
  if (timeOrder > 0) return incoming;
  if (timeOrder < 0) return current;
  if (incoming.revision > current.revision) return incoming;
  if (incoming.revision < current.revision) return current;
  return incoming.deviceId.compareTo(current.deviceId) > 0 ? incoming : current;
}

class ProgressCheckpoint {
  const ProgressCheckpoint({required this.progress, required this.savedAt, required this.source});

  final ReadingProgress progress;
  final DateTime savedAt;
  final String source;
}
