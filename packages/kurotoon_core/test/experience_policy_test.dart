import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

void main() {
  const policy = GalaxyEffectPolicy();

  test('reduces particle workload for low-memory and battery-saver devices', () {
    final normal = policy.resolve(const GalaxyEnvironment(refreshRateHz: 60));
    final lowPower = policy.resolve(const GalaxyEnvironment(
      refreshRateHz: 60,
      lowEndDevice: true,
      availableMemoryMb: 1024,
      batterySaver: true,
    ));
    expect(lowPower.animatedParticleCount, lessThan(normal.animatedParticleCount));
    expect(lowPower.updateRateHz, lessThanOrEqualTo(20));
    expect(lowPower.enableShootingStars, isFalse);
  });

  test('pauses all galaxy updates when the app is hidden', () {
    final budget = policy.resolve(const GalaxyEnvironment(refreshRateHz: 60, appVisible: false));
    expect(budget.paused, isTrue);
    expect(budget.animatedParticleCount, 0);
    expect(budget.updateRateHz, 0);
  });

  test('reduced-motion mode disables animated particles and touch effects', () {
    final budget = policy.resolve(const GalaxyEnvironment(refreshRateHz: 60, reducedMotion: true));
    expect(budget.animatedParticleCount, 0);
    expect(budget.enableTouchRipples, isFalse);
    expect(budget.enableShootingStars, isFalse);
  });

  test('audio and haptics are off unless individually enabled', () {
    const settings = ReaderExperienceSettings();
    expect(settings.allows(ReaderEventKind.music), isFalse);
    expect(settings.allows(ReaderEventKind.dialogue), isFalse);
    expect(settings.allows(ReaderEventKind.haptic), isFalse);

    final enabled = settings.copyWith(
      musicEnabled: true,
      hapticsEnabled: true,
      dialogueEnabled: true,
      voicePackId: 'voice-en',
    );
    expect(enabled.allows(ReaderEventKind.music), isTrue);
    expect(enabled.allows(ReaderEventKind.haptic), isTrue);
    expect(enabled.allows(ReaderEventKind.dialogue), isTrue);
    expect(enabled.copyWith(globalPaused: true).allows(ReaderEventKind.music), isFalse);
  });
}
