import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_flutter/ui/galaxy_motion_policy.dart';

void main() {
  group('shouldAnimateGalaxy', () {
    test('animates only when the user and platform allow foreground motion', () {
      expect(
        shouldAnimateGalaxy(
          userEnabled: true,
          systemReducedMotion: false,
          appResumed: true,
        ),
        isTrue,
      );
      expect(
        shouldAnimateGalaxy(
          userEnabled: false,
          systemReducedMotion: false,
          appResumed: true,
        ),
        isFalse,
      );
      expect(
        shouldAnimateGalaxy(
          userEnabled: true,
          systemReducedMotion: true,
          appResumed: true,
        ),
        isFalse,
      );
      expect(
        shouldAnimateGalaxy(
          userEnabled: true,
          systemReducedMotion: false,
          appResumed: false,
        ),
        isFalse,
      );
    });
  });

  group('nextGalaxyEffectQuality', () {
    test('drops one tier only after a sustained run of slow frames', () {
      expect(
        nextGalaxyEffectQuality(
          currentQuality: 2,
          consecutiveSlowFrames: 7,
          consecutiveFastFrames: 0,
        ),
        2,
      );
      expect(
        nextGalaxyEffectQuality(
          currentQuality: 2,
          consecutiveSlowFrames: 8,
          consecutiveFastFrames: 0,
        ),
        1,
      );
      expect(
        nextGalaxyEffectQuality(
          currentQuality: 1,
          consecutiveSlowFrames: 8,
          consecutiveFastFrames: 0,
        ),
        0,
      );
    });

    test('restores one tier only after sustained healthy frames', () {
      expect(
        nextGalaxyEffectQuality(
          currentQuality: 0,
          consecutiveSlowFrames: 0,
          consecutiveFastFrames: 239,
        ),
        0,
      );
      expect(
        nextGalaxyEffectQuality(
          currentQuality: 0,
          consecutiveSlowFrames: 0,
          consecutiveFastFrames: 240,
        ),
        1,
      );
      expect(
        nextGalaxyEffectQuality(
          currentQuality: 1,
          consecutiveSlowFrames: 0,
          consecutiveFastFrames: 240,
        ),
        2,
      );
    });

    test('keeps quality inside its supported range', () {
      expect(
        nextGalaxyEffectQuality(
          currentQuality: -1,
          consecutiveSlowFrames: 0,
          consecutiveFastFrames: 0,
        ),
        0,
      );
      expect(
        nextGalaxyEffectQuality(
          currentQuality: 9,
          consecutiveSlowFrames: 0,
          consecutiveFastFrames: 0,
        ),
        2,
      );
    });
  });
}
