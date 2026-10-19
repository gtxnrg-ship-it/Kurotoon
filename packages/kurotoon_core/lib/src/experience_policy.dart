import 'reader_timeline.dart';

enum ReaderPreset { classic, atmosphere, cinematic }
enum GalaxyQualityPreference { automatic, reduced, standard, high }

class ReaderExperienceSettings {
  const ReaderExperienceSettings({
    this.preset = ReaderPreset.classic,
    this.globalPaused = false,
    this.musicEnabled = false,
    this.ambienceEnabled = false,
    this.soundEffectsEnabled = false,
    this.dialogueEnabled = false,
    this.narrationEnabled = false,
    this.hapticsEnabled = false,
    this.voicePackId,
    this.galaxyMotionEnabled = true,
    this.galaxyMotionIntensity = 0.65,
    this.galaxyQuality = GalaxyQualityPreference.automatic,
    this.limitBackgroundActivity = true,
  }) : assert(galaxyMotionIntensity >= 0 && galaxyMotionIntensity <= 1);

  final ReaderPreset preset;
  final bool globalPaused;
  final bool musicEnabled;
  final bool ambienceEnabled;
  final bool soundEffectsEnabled;
  final bool dialogueEnabled;
  final bool narrationEnabled;
  final bool hapticsEnabled;
  final String? voicePackId;
  final bool galaxyMotionEnabled;
  final double galaxyMotionIntensity;
  final GalaxyQualityPreference galaxyQuality;
  final bool limitBackgroundActivity;

  bool allows(ReaderEventKind kind) {
    if (globalPaused) return false;
    return switch (kind) {
      ReaderEventKind.music => musicEnabled,
      ReaderEventKind.ambience => ambienceEnabled,
      ReaderEventKind.soundEffect => soundEffectsEnabled,
      ReaderEventKind.dialogue => dialogueEnabled && voicePackId != null,
      ReaderEventKind.narration => narrationEnabled && voicePackId != null,
      ReaderEventKind.haptic => hapticsEnabled,
    };
  }

  ReaderExperienceSettings copyWith({
    ReaderPreset? preset,
    bool? globalPaused,
    bool? musicEnabled,
    bool? ambienceEnabled,
    bool? soundEffectsEnabled,
    bool? dialogueEnabled,
    bool? narrationEnabled,
    bool? hapticsEnabled,
    String? voicePackId,
    bool clearVoicePack = false,
    bool? galaxyMotionEnabled,
    double? galaxyMotionIntensity,
    GalaxyQualityPreference? galaxyQuality,
    bool? limitBackgroundActivity,
  }) =>
      ReaderExperienceSettings(
        preset: preset ?? this.preset,
        globalPaused: globalPaused ?? this.globalPaused,
        musicEnabled: musicEnabled ?? this.musicEnabled,
        ambienceEnabled: ambienceEnabled ?? this.ambienceEnabled,
        soundEffectsEnabled: soundEffectsEnabled ?? this.soundEffectsEnabled,
        dialogueEnabled: dialogueEnabled ?? this.dialogueEnabled,
        narrationEnabled: narrationEnabled ?? this.narrationEnabled,
        hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
        voicePackId: clearVoicePack ? null : (voicePackId ?? this.voicePackId),
        galaxyMotionEnabled: galaxyMotionEnabled ?? this.galaxyMotionEnabled,
        galaxyMotionIntensity: galaxyMotionIntensity ?? this.galaxyMotionIntensity,
        galaxyQuality: galaxyQuality ?? this.galaxyQuality,
        limitBackgroundActivity: limitBackgroundActivity ?? this.limitBackgroundActivity,
      );
}

class GalaxyEnvironment {
  const GalaxyEnvironment({
    required this.refreshRateHz,
    this.lowEndDevice = false,
    this.availableMemoryMb = 4096,
    this.batterySaver = false,
    this.reducedMotion = false,
    this.appVisible = true,
    this.userIntensity = 0.65,
  })  : assert(refreshRateHz > 0),
        assert(availableMemoryMb >= 0),
        assert(userIntensity >= 0 && userIntensity <= 1);

  final double refreshRateHz;
  final bool lowEndDevice;
  final int availableMemoryMb;
  final bool batterySaver;
  final bool reducedMotion;
  final bool appVisible;
  final double userIntensity;
}

class GalaxyEffectBudget {
  const GalaxyEffectBudget({
    required this.animatedParticleCount,
    required this.nebulaLayerCount,
    required this.blurSigma,
    required this.updateRateHz,
    required this.enableTouchRipples,
    required this.enableShootingStars,
    required this.paused,
    required this.frameBudgetMicros,
  });

  final int animatedParticleCount;
  final int nebulaLayerCount;
  final double blurSigma;
  final double updateRateHz;
  final bool enableTouchRipples;
  final bool enableShootingStars;
  final bool paused;
  final int frameBudgetMicros;
}

class GalaxyEffectPolicy {
  const GalaxyEffectPolicy();

  GalaxyEffectBudget resolve(
    GalaxyEnvironment environment, {
    GalaxyQualityPreference preference = GalaxyQualityPreference.automatic,
    bool motionEnabled = true,
    double motionIntensity = 0.65,
  }) {
    final frameBudget = (1000000 / environment.refreshRateHz).round();
    if (!environment.appVisible) {
      return GalaxyEffectBudget(
        animatedParticleCount: 0,
        nebulaLayerCount: 0,
        blurSigma: 0,
        updateRateHz: 0,
        enableTouchRipples: false,
        enableShootingStars: false,
        paused: true,
        frameBudgetMicros: frameBudget,
      );
    }

    final lowEnd = environment.lowEndDevice || environment.availableMemoryMb < 2048;
    var particles = lowEnd ? 56 : 144;
    var nebulaLayers = lowEnd ? 2 : 4;
    var blur = lowEnd ? 5.0 : 12.0;
    var updates = environment.refreshRateHz.clamp(24.0, 60.0).toDouble();

    switch (preference) {
      case GalaxyQualityPreference.automatic:
        break;
      case GalaxyQualityPreference.reduced:
        particles = (particles * 0.45).round();
        nebulaLayers = nebulaLayers > 1 ? nebulaLayers - 1 : 1;
        blur *= 0.6;
        updates = updates < 30 ? updates : 30;
      case GalaxyQualityPreference.standard:
        particles = particles.clamp(48, 100);
        nebulaLayers = nebulaLayers.clamp(1, 3);
        blur = blur.clamp(3.0, 8.0).toDouble();
      case GalaxyQualityPreference.high:
        particles = lowEnd ? 72 : 200;
        nebulaLayers = lowEnd ? 2 : 5;
        blur = lowEnd ? 6 : 15;
    }

    final intensity = (environment.userIntensity * motionIntensity).clamp(0.0, 1.0).toDouble();
    particles = (particles * intensity).round();
    if (environment.batterySaver) {
      particles = (particles * 0.5).round();
      nebulaLayers = nebulaLayers > 1 ? nebulaLayers - 1 : 1;
      updates = updates < 20 ? updates : 20;
      blur *= 0.7;
    }

    if (!motionEnabled || environment.reducedMotion || intensity == 0) {
      return GalaxyEffectBudget(
        animatedParticleCount: 0,
        nebulaLayerCount: 1,
        blurSigma: 0,
        updateRateHz: 1,
        enableTouchRipples: false,
        enableShootingStars: false,
        paused: false,
        frameBudgetMicros: frameBudget,
      );
    }

    return GalaxyEffectBudget(
      animatedParticleCount: particles,
      nebulaLayerCount: nebulaLayers,
      blurSigma: blur,
      updateRateHz: updates,
      enableTouchRipples: !lowEnd && !environment.batterySaver,
      enableShootingStars: !lowEnd && !environment.batterySaver && preference != GalaxyQualityPreference.reduced,
      paused: false,
      frameBudgetMicros: frameBudget,
    );
  }
}
