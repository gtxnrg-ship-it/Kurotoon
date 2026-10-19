enum ReaderEventKind { music, ambience, soundEffect, dialogue, narration, haptic }

class ReaderCue {
  const ReaderCue({
    required this.id,
    required this.chapterId,
    required this.positionMillis,
    required this.kind,
    required this.payload,
    this.confidence = 1,
    this.creatorAuthored = false,
    this.userApproved = false,
  });

  final String id;
  final String chapterId;
  final int positionMillis;
  final ReaderEventKind kind;
  final String payload;
  final double confidence;
  final bool creatorAuthored;
  final bool userApproved;
}

class ReaderTimelinePreferences {
  ReaderTimelinePreferences({
    Set<ReaderEventKind> enabledKinds = const {},
    this.minimumConfidence = 0.90,
    this.allowInferredDialogue = false,
  }) : enabledKinds = Set.unmodifiable(enabledKinds) {
    if (!minimumConfidence.isFinite || minimumConfidence < 0 || minimumConfidence > 1) {
      throw ArgumentError.value(minimumConfidence, 'minimumConfidence');
    }
  }

  final Set<ReaderEventKind> enabledKinds;
  final double minimumConfidence;
  final bool allowInferredDialogue;
}

class ReaderTimeline {
  const ReaderTimeline();

  /// Returns cues in a crossed position interval. No channel is enabled by default.
  /// UI/audio adapters should cancel queued playback when chapter or playback state changes.
  List<ReaderCue> cuesCrossed({
    required Iterable<ReaderCue> cues,
    required String chapterId,
    required int fromMillis,
    required int toMillis,
    required ReaderTimelinePreferences preferences,
  }) {
    if (toMillis < fromMillis) return const [];
    final due = cues.where((cue) {
      if (cue.chapterId != chapterId ||
          cue.positionMillis <= fromMillis ||
          cue.positionMillis > toMillis ||
          !preferences.enabledKinds.contains(cue.kind)) {
        return false;
      }
      if (cue.confidence < 0 || cue.confidence > 1) return false;
      if (cue.kind == ReaderEventKind.dialogue &&
          !cue.creatorAuthored &&
          !cue.userApproved &&
          !preferences.allowInferredDialogue) {
        return false;
      }
      return cue.creatorAuthored || cue.userApproved || cue.confidence >= preferences.minimumConfidence;
    }).toList()
      ..sort((a, b) {
        final byPosition = a.positionMillis.compareTo(b.positionMillis);
        return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
      });
    return List.unmodifiable(due);
  }
}
