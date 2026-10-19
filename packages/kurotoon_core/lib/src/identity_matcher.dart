import 'models.dart';

enum IdentityVerdict { safeMatch, needsReview, distinct }

class IdentityDecision {
  const IdentityDecision({
    required this.verdict,
    required this.score,
    required this.evidence,
  });

  final IdentityVerdict verdict;
  final double score;
  final List<String> evidence;

  bool get safeToMerge => verdict == IdentityVerdict.safeMatch;
}

class WorkIdentityMatcher {
  const WorkIdentityMatcher({
    this.safeMergeThreshold = 0.90,
    this.reviewThreshold = 0.62,
  });

  final double safeMergeThreshold;
  final double reviewThreshold;

  IdentityDecision compare(WorkRecord work, WorkCandidate candidate) {
    if (work.lockedDistinctIdentity) {
      return const IdentityDecision(
        verdict: IdentityVerdict.distinct,
        score: 0,
        evidence: ['Existing work identity is explicitly locked as distinct'],
      );
    }

    final evidence = <String>[];
    final leftTitles = <String>{normalizeTitle(work.title), ...work.alternateTitles.map(normalizeTitle)}
      ..remove('');
    final rightTitles = <String>{normalizeTitle(candidate.title), ...candidate.alternateTitles.map(normalizeTitle)}
      ..remove('');

    double titleScore = 0;
    for (final left in leftTitles) {
      for (final right in rightTitles) {
        final score = _similarity(left, right);
        if (score > titleScore) titleScore = score;
      }
    }
    if (titleScore >= 0.999) {
      evidence.add('Primary or alternate title matches exactly after normalization');
    } else if (titleScore >= 0.50) {
      evidence.add('Title token overlap: ${(titleScore * 100).round()}%');
    }

    final leftCreators = work.creatorNames.map(normalizeTitle).where((v) => v.isNotEmpty).toSet();
    final rightCreators = candidate.creatorNames.map(normalizeTitle).where((v) => v.isNotEmpty).toSet();
    final creatorMatch = leftCreators.intersection(rightCreators).isNotEmpty;
    if (creatorMatch) evidence.add('At least one creator name matches');

    final yearConflict = work.year != null &&
        candidate.year != null &&
        (work.year! - candidate.year!).abs() > 2;
    if (yearConflict) evidence.add('Publication years conflict');
    final yearMatch = work.year != null && candidate.year != null && work.year == candidate.year;
    if (yearMatch) evidence.add('Publication year matches');

    final formatConflict = work.format != WorkFormat.unknown &&
        candidate.format != WorkFormat.unknown &&
        work.format != candidate.format;
    if (formatConflict) evidence.add('Work formats conflict');
    final formatMatch = work.format != WorkFormat.unknown && work.format == candidate.format;
    if (formatMatch) evidence.add('Work format matches');

    if (yearConflict || formatConflict) {
      return IdentityDecision(
        verdict: IdentityVerdict.distinct,
        score: (titleScore * 0.72).clamp(0.0, 1.0),
        evidence: List.unmodifiable(evidence),
      );
    }

    // A title alone is deliberately insufficient to auto-merge works.
    var score = titleScore * 0.72;
    if (creatorMatch) score += 0.16;
    if (yearMatch) score += 0.08;
    if (formatMatch) score += 0.04;
    score = score.clamp(0.0, 1.0);

    final verdict = score >= safeMergeThreshold
        ? IdentityVerdict.safeMatch
        : score >= reviewThreshold
            ? IdentityVerdict.needsReview
            : IdentityVerdict.distinct;

    if (evidence.isEmpty) evidence.add('Insufficient matching evidence');
    return IdentityDecision(verdict: verdict, score: score, evidence: List.unmodifiable(evidence));
  }

  static String normalizeTitle(String value) {
    // Deliberately retain non-Latin letters so Japanese, Korean, and Chinese titles survive.
    final cleaned = value
        .toLowerCase()
        .replaceAll(RegExp(r'''[.,:;!?'"\x60~!@#$%^&*(){}\[\]<>\\/|_+=-]+'''), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned;
  }

  static double _similarity(String left, String right) {
    if (left.isEmpty || right.isEmpty) return 0;
    if (left == right) return 1;
    final a = left.split(' ').where((t) => t.isNotEmpty).toSet();
    final b = right.split(' ').where((t) => t.isNotEmpty).toSet();
    if (a.isEmpty || b.isEmpty) return 0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    return union == 0 ? 0 : intersection / union;
  }
}
