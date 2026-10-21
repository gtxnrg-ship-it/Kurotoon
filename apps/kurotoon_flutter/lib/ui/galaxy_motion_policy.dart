/// Deterministic guard for the animated Galaxy layer.
///
/// Motion runs only when the user's preference allows it, the OS has not
/// requested reduced animation, and the app is in the foreground.
bool shouldAnimateGalaxy({
  required bool userEnabled,
  required bool systemReducedMotion,
  required bool appResumed,
}) =>
    userEnabled && !systemReducedMotion && appResumed;

/// Adapts blur/star work gradually instead of changing quality on one noisy
/// frame. Quality 0 is lean, 1 is balanced, and 2 is full detail.
int nextGalaxyEffectQuality({
  required int currentQuality,
  required int consecutiveSlowFrames,
  required int consecutiveFastFrames,
}) {
  final quality = currentQuality.clamp(0, 2).toInt();
  if (consecutiveSlowFrames >= 8 && quality > 0) return quality - 1;
  if (consecutiveFastFrames >= 240 && quality < 2) return quality + 1;
  return quality;
}
