import 'dart:convert';

/// Whitelisted provider-health fields suitable for an explicitly reviewed
/// diagnostic export. Raw exception messages and request data have no field
/// in this model, so they cannot accidentally leak into the serialized bundle.
class ProviderDiagnosticExportRecord {
  const ProviderDiagnosticExportRecord({
    required this.providerId,
    required this.providerName,
    required this.enabled,
    required this.healthState,
    required this.capabilities,
    required this.consecutiveFailures,
    this.lastStatus,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.remainingCooldown,
  });

  final String providerId;
  final String providerName;
  final bool enabled;
  final String healthState;
  final List<String> capabilities;
  final int consecutiveFailures;
  final String? lastStatus;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final Duration? remainingCooldown;
}

/// Produces a compact, versioned JSON bundle with a deliberate field allowlist.
///
/// This is not a full application dump. It contains source identifiers, the
/// source labels/capabilities shown in diagnostics, and health timing/counts.
/// It excludes request bodies, raw errors, query/title history, reading
/// positions, file paths, full URLs, account identifiers and credentials.
String buildRedactedProviderDiagnosticExport({
  required DateTime generatedAt,
  required Iterable<ProviderDiagnosticExportRecord> providers,
}) {
  final rows = providers.map((provider) {
    final capabilities = provider.capabilities
        .map(_safeCapability)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    final failures = provider.consecutiveFailures.clamp(0, 1000000).toInt();
    final cooldownSeconds =
        (provider.remainingCooldown?.inSeconds ?? 0).clamp(0, 86400).toInt();
    return <String, Object?>{
      'providerId': _safeProviderId(provider.providerId),
      'providerName': _redactLabel(provider.providerName),
      'enabled': provider.enabled,
      'healthState': _safeEnumLabel(provider.healthState),
      'capabilities': capabilities,
      'consecutiveFailures': failures,
      'lastStatus': provider.lastStatus == null
          ? null
          : _safeEnumLabel(provider.lastStatus!),
      'lastSuccessAtUtc': provider.lastSuccessAt?.toUtc().toIso8601String(),
      'lastFailureAtUtc': provider.lastFailureAt?.toUtc().toIso8601String(),
      'remainingCooldownSeconds': cooldownSeconds,
    };
  }).toList()
    ..sort((a, b) => (a['providerId']! as String)
        .compareTo(b['providerId']! as String));

  final document = <String, Object?>{
    'format': 'kurotoon-provider-diagnostics',
    'schemaVersion': 1,
    'generatedAtUtc': generatedAt.toUtc().toIso8601String(),
    'providerCount': rows.length,
    'privacy': <String, Object?>{
      'scope': 'provider-health-only',
      'excluded': [
        'raw error messages and stack traces',
        'HTTP request/response bodies and headers',
        'full URLs, filesystem paths and cache contents',
        'search queries, story titles and creator lookups',
        'library membership and reading progress',
        'account identifiers, tokens, passwords and credentials',
      ],
      'reviewBeforeSharing': true,
    },
    'providers': rows,
  };
  return const JsonEncoder.withIndent('  ').convert(document);
}

String _safeProviderId(String value) {
  final trimmed = value.trim();
  return RegExp(r'^[A-Za-z0-9._-]{1,96}$').hasMatch(trimmed)
      ? trimmed
      : '[redacted-provider-id]';
}

String? _safeCapability(String value) {
  final trimmed = value.trim();
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,47}$').hasMatch(trimmed)) {
    return null;
  }
  return trimmed;
}

String _safeEnumLabel(String value) {
  final trimmed = value.trim();
  return RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(trimmed)
      ? trimmed
      : '[redacted]';
}

String _redactLabel(String value) {
  var safe = value.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ').trim();
  safe = safe.replaceAll(
    RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    '[redacted credential]',
  );
  safe = safe.replaceAll(
    RegExp(
      r'\b(?:token|api[-_ ]?key|authorization|password|secret)\s*[:=]\s*[^\s,;]+',
      caseSensitive: false,
    ),
    '[redacted credential]',
  );
  safe = safe.replaceAll(
    RegExp(r'https?://[^\s,;]+', caseSensitive: false),
    '[redacted URL]',
  );
  if (safe.length > 120) safe = safe.substring(0, 120);
  return safe;
}
