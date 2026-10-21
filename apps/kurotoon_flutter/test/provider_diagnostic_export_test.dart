import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_flutter/services/provider_diagnostic_export.dart';

void main() {
  group('buildRedactedProviderDiagnosticExport', () {
    test('exports deterministic whitelisted source-health data', () {
      final output = buildRedactedProviderDiagnosticExport(
        generatedAt: DateTime.utc(2026, 10, 21, 12, 30),
        providers: [
          ProviderDiagnosticExportRecord(
            providerId: 'community-source',
            providerName: 'Community Catalog',
            enabled: true,
            healthState: 'degraded',
            capabilities: const ['pages', 'chapters', 'pages'],
            consecutiveFailures: 2,
            lastStatus: 'networkFailure',
            lastSuccessAt: DateTime.utc(2026, 10, 21, 12, 0),
            lastFailureAt: DateTime.utc(2026, 10, 21, 12, 2),
            remainingCooldown: const Duration(seconds: 12),
          ),
          const ProviderDiagnosticExportRecord(
            providerId: 'mangadex',
            providerName: 'MangaDex',
            enabled: true,
            healthState: 'healthy',
            capabilities: ['chapters', 'pages'],
            consecutiveFailures: 0,
          ),
        ],
      );

      final decoded = jsonDecode(output) as Map<String, dynamic>;
      expect(decoded['format'], 'kurotoon-provider-diagnostics');
      expect(decoded['schemaVersion'], 1);
      expect(decoded['providerCount'], 2);
      final rows = decoded['providers'] as List<dynamic>;
      expect((rows.first as Map<String, dynamic>)['providerId'], 'community-source');
      expect((rows.first as Map<String, dynamic>)['capabilities'], ['chapters', 'pages']);
      expect((rows.first as Map<String, dynamic>)['remainingCooldownSeconds'], 12);
      expect(decoded['privacy']['reviewBeforeSharing'], isTrue);
      expect(output, isNot(contains('lastMessage')));
      expect(output, isNot(contains('stackTrace')));
    });

    test('redacts URLs and token-like text embedded in untrusted labels', () {
      final output = buildRedactedProviderDiagnosticExport(
        generatedAt: DateTime.utc(2026, 10, 21),
        providers: const [
          ProviderDiagnosticExportRecord(
            providerId: 'bad source id https://private.example/?token=do-not-leak',
            providerName: 'Private source token=abc123 https://private.example/path?key=secret',
            enabled: false,
            healthState: 'degraded',
            capabilities: ['pages'],
            consecutiveFailures: 1,
            lastStatus: 'failed',
          ),
        ],
      );

      expect(output, isNot(contains('https://private.example')));
      expect(output, isNot(contains('abc123')));
      expect(output, isNot(contains('do-not-leak')));
      expect(output, isNot(contains('key=secret')));
      final decoded = jsonDecode(output) as Map<String, dynamic>;
      final row = (decoded['providers'] as List<dynamic>).single as Map<String, dynamic>;
      expect(row['providerId'], '[redacted-provider-id]');
      expect(row['providerName'], contains('[redacted credential]'));
      expect(row['providerName'], contains('[redacted URL]'));
    });

    test('clamps counters and cooldown and excludes unsupported fields', () {
      final output = buildRedactedProviderDiagnosticExport(
        generatedAt: DateTime.utc(2026, 10, 21),
        providers: [
          ProviderDiagnosticExportRecord(
            providerId: 'mangadex',
            providerName: 'MangaDex',
            enabled: true,
            healthState: 'healthy',
            capabilities: const ['valid', 'contains private/path'],
            consecutiveFailures: -6,
            remainingCooldown: const Duration(days: 8),
          ),
        ],
      );

      final decoded = jsonDecode(output) as Map<String, dynamic>;
      final row = (decoded['providers'] as List<dynamic>).single as Map<String, dynamic>;
      expect(row['consecutiveFailures'], 0);
      expect(row['remainingCooldownSeconds'], 86400);
      expect(row['capabilities'], ['valid']);
      expect(output, isNot(contains('private/path')));
    });
  });
}
