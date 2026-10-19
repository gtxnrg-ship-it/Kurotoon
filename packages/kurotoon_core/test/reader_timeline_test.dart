import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

void main() {
  test('channels default to off and inferred dialogue needs opt-in', () {
    const cue = ReaderCue(
      id: 'line-1',
      chapterId: 'chapter-1',
      positionMillis: 1500,
      kind: ReaderEventKind.dialogue,
      payload: 'Hello',
      confidence: 1,
    );
    const timeline = ReaderTimeline();
    final disabled = timeline.cuesCrossed(
      cues: const [cue],
      chapterId: 'chapter-1',
      fromMillis: 1000,
      toMillis: 2000,
      preferences: ReaderTimelinePreferences(),
    );
    expect(disabled, isEmpty);

    final enabled = timeline.cuesCrossed(
      cues: const [cue],
      chapterId: 'chapter-1',
      fromMillis: 1000,
      toMillis: 2000,
      preferences: ReaderTimelinePreferences(
        enabledKinds: {ReaderEventKind.dialogue},
        allowInferredDialogue: true,
      ),
    );
    expect(enabled, hasLength(1));
  });

  test('never emits a cue belonging to another chapter or an uncertain event', () {
    const timeline = ReaderTimeline();
    const cues = [
      ReaderCue(id: 'wrong', chapterId: 'chapter-2', positionMillis: 1500, kind: ReaderEventKind.haptic, payload: 'tap', confidence: 1),
      ReaderCue(id: 'weak', chapterId: 'chapter-1', positionMillis: 1600, kind: ReaderEventKind.haptic, payload: 'hit', confidence: 0.4),
    ];
    final results = timeline.cuesCrossed(
      cues: cues,
      chapterId: 'chapter-1',
      fromMillis: 1000,
      toMillis: 2000,
      preferences: ReaderTimelinePreferences(
        enabledKinds: {ReaderEventKind.haptic},
        minimumConfidence: 0.9,
      ),
    );
    expect(results, isEmpty);
  });
}
