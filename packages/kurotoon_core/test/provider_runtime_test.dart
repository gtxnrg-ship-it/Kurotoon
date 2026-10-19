import 'dart:async';

import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

class FakeProvider implements SourceProvider {
  FakeProvider({
    required this.descriptor,
    required this.handler,
  });

  @override
  final ProviderDescriptor descriptor;
  final Future<ProviderResponse<List<WorkCandidate>>> Function(
    String,
    CancellationToken,
  ) handler;

  @override
  Future<ProviderResponse<List<WorkCandidate>>> search(
    String query, {
    required CancellationToken cancellationToken,
  }) => handler(query, cancellationToken);
}

void main() {
  ProviderDescriptor descriptor(String id, {bool builtIn = false, bool enabled = true}) =>
      ProviderDescriptor(
        id: id,
        name: id,
        homepage: Uri.parse('https://$id.example.org'),
        capabilities: const {ProviderCapability.search},
        isBuiltIn: builtIn,
        enabledByDefault: enabled,
      );

  test('deduplicates provider listings and keeps partial source failures explicit', () async {
    final registry = ProviderRegistry()
      ..register(FakeProvider(
        descriptor: descriptor('a', builtIn: true),
        handler: (query, token) async => ProviderResponse(
          status: ProviderResultStatus.success,
          data: [
            WorkCandidate(
              providerId: 'a',
              externalId: 'same',
              title: 'Series',
              providerUrl: Uri.parse('https://a.example.org/series/same'),
            ),
          ],
        ),
      ))
      ..register(FakeProvider(
        descriptor: descriptor('b'),
        handler: (query, token) async => const ProviderResponse(
          status: ProviderResultStatus.blocked,
          message: 'Source temporarily blocked',
        ),
      ));

    final result = await ProviderCoordinator(registry).search(' series ');
    expect(result.candidates, hasLength(1));
    expect(result.hasPartialFailures, isTrue);
    expect(result.results, hasLength(2));
  });

  test('limits concurrently active provider calls', () async {
    final registry = ProviderRegistry();
    var active = 0;
    var peak = 0;
    for (var i = 0; i < 8; i++) {
      final id = 'source$i';
      registry.register(FakeProvider(
        descriptor: descriptor(id),
        handler: (query, token) async {
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 15));
          active--;
          return const ProviderResponse(status: ProviderResultStatus.success, data: []);
        },
      ));
    }
    await ProviderCoordinator(registry, maxConcurrentProviders: 3).search('test');
    expect(peak, lessThanOrEqualTo(3));
  });

  test('built-in source may be disabled but cannot be removed', () {
    final registry = ProviderRegistry()
      ..register(FakeProvider(
        descriptor: descriptor('mangadex', builtIn: true),
        handler: (query, token) async => const ProviderResponse(status: ProviderResultStatus.success, data: []),
      ));
    registry.setEnabled('mangadex', false);
    expect(registry.enabled, isEmpty);
    expect(() => registry.removeCommunityProvider('mangadex'), throwsStateError);
    expect(() => registry.setEnabled('missing', false), throwsArgumentError);
  });

  test('times out an unresponsive provider and signals cooperative cancellation', () async {
    final observedCancel = Completer<void>();
    final never = Completer<ProviderResponse<List<WorkCandidate>>>();
    final registry = ProviderRegistry()
      ..register(FakeProvider(
        descriptor: descriptor('slow'),
        handler: (query, token) {
          token.onCancel((_) {
            if (!observedCancel.isCompleted) observedCancel.complete();
          });
          return never.future;
        },
      ));
    final batch = await ProviderCoordinator(
      registry,
      providerTimeout: const Duration(milliseconds: 10),
    ).search('test');
    expect(batch.results.single.response.status, ProviderResultStatus.timedOut);
    expect(observedCancel.isCompleted, isTrue);
  });
  test('backs off a failing source and resets health after a successful retry', () async {
    var now = DateTime.utc(2026, 1, 1);
    var calls = 0;
    var shouldSucceed = false;
    final health = ProviderHealthTracker(
      clock: () => now,
      failureThreshold: 2,
      baseCooldown: const Duration(seconds: 10),
      maxCooldown: const Duration(minutes: 1),
    );
    final registry = ProviderRegistry()
      ..register(FakeProvider(
        descriptor: descriptor('flaky'),
        handler: (query, token) async {
          calls++;
          return shouldSucceed
              ? const ProviderResponse(status: ProviderResultStatus.success, data: [])
              : const ProviderResponse(status: ProviderResultStatus.failed, message: 'temporary failure');
        },
      ));
    final coordinator = ProviderCoordinator(registry, healthTracker: health);

    expect((await coordinator.search('test')).results.single.response.status, ProviderResultStatus.failed);
    expect(health.snapshotFor('flaky').state, ProviderHealthState.degraded);
    expect(health.snapshotFor('flaky').consecutiveFailures, 1);

    expect((await coordinator.search('test')).results.single.response.status, ProviderResultStatus.failed);
    expect(health.snapshotFor('flaky').state, ProviderHealthState.coolingDown);
    expect(health.remainingCooldown('flaky'), const Duration(seconds: 10));

    final skipped = await coordinator.search('test');
    expect(skipped.results.single.response.status, ProviderResultStatus.rateLimited);
    expect(calls, 2, reason: 'A source in cooldown must not receive another request.');

    now = now.add(const Duration(seconds: 11));
    shouldSucceed = true;
    expect((await coordinator.search('test')).results.single.response.status, ProviderResultStatus.success);
    expect(calls, 3);
    expect(health.snapshotFor('flaky').state, ProviderHealthState.healthy);
    expect(health.snapshotFor('flaky').consecutiveFailures, 0);
  });

  test('honours upstream Retry-After without repeatedly querying a rate-limited source', () async {
    var now = DateTime.utc(2026, 1, 1);
    var calls = 0;
    final health = ProviderHealthTracker(clock: () => now);
    final registry = ProviderRegistry()
      ..register(FakeProvider(
        descriptor: descriptor('limited'),
        handler: (query, token) async {
          calls++;
          return const ProviderResponse(
            status: ProviderResultStatus.rateLimited,
            message: 'Please slow down',
            retryAfter: Duration(minutes: 1),
          );
        },
      ));
    final coordinator = ProviderCoordinator(registry, healthTracker: health);

    expect((await coordinator.search('test')).results.single.response.status, ProviderResultStatus.rateLimited);
    now = now.add(const Duration(seconds: 30));
    final skipped = await coordinator.search('test');
    expect(skipped.results.single.response.status, ProviderResultStatus.rateLimited);
    expect(skipped.results.single.response.retryAfter, const Duration(seconds: 30));
    expect(calls, 1);
  });

  test('cancellation does not increase provider failure streak', () {
    final health = ProviderHealthTracker();
    health.record(
      'source',
      const ProviderResponse(status: ProviderResultStatus.cancelled, message: 'user cancelled'),
    );
    expect(health.snapshotFor('source').consecutiveFailures, 0);
    expect(health.snapshotFor('source').state, ProviderHealthState.healthy);
  });

  test('provider health snapshots restore validated cooldown state without raw errors', () {
    var now = DateTime.utc(2026, 1, 1);
    final original = ProviderHealthTracker(
      clock: () => now,
      failureThreshold: 2,
      baseCooldown: const Duration(seconds: 10),
      maxCooldown: const Duration(minutes: 1),
    );
    original.record(
      'source',
      const ProviderResponse(status: ProviderResultStatus.failed, message: 'private URL should not persist'),
    );
    original.record(
      'source',
      const ProviderResponse(status: ProviderResultStatus.timedOut, message: 'request details should not persist'),
    );
    final json = original.snapshotFor('source').toJson();
    expect(json.containsKey('lastMessage'), isFalse);

    final restored = ProviderHealthTracker(
      clock: () => now,
      failureThreshold: 2,
      baseCooldown: const Duration(seconds: 10),
      maxCooldown: const Duration(minutes: 1),
    );
    expect(restored.restoreFromJson('source', json), isTrue);
    expect(restored.snapshotFor('source').state, ProviderHealthState.coolingDown);
    expect(restored.remainingCooldown('source'), const Duration(seconds: 10));

    expect(restored.restoreFromJson('bad', {'consecutiveFailures': -1}), isFalse);
    now = now.add(const Duration(seconds: 11));
    expect(restored.snapshotFor('source').state, ProviderHealthState.degraded);
  });

  test('empty search does not dispatch to any provider', () async {
    var calls = 0;
    final registry = ProviderRegistry()
      ..register(FakeProvider(
        descriptor: descriptor('counted'),
        handler: (query, token) async {
          calls++;
          return const ProviderResponse(status: ProviderResultStatus.success, data: []);
        },
      ));

    final batch = await ProviderCoordinator(registry).search('   ');

    expect(calls, 0);
    expect(batch.results, isEmpty);
    expect(batch.cancelled, isFalse);
  });

  test('parent cancellation returns even if a provider ignores its token', () async {
    final started = Completer<void>();
    final observedCancel = Completer<void>();
    final never = Completer<ProviderResponse<List<WorkCandidate>>>();
    final parent = CancellationToken();
    final registry = ProviderRegistry()
      ..register(FakeProvider(
        descriptor: descriptor('uncooperative'),
        handler: (query, token) {
          started.complete();
          token.onCancel((_) {
            if (!observedCancel.isCompleted) observedCancel.complete();
          });
          return never.future;
        },
      ));

    final pending = ProviderCoordinator(
      registry,
      providerTimeout: const Duration(seconds: 2),
    ).search('series', cancellationToken: parent);
    await started.future;
    parent.cancel('A newer search replaced this one');
    final batch = await pending;

    expect(batch.cancelled, isTrue);
    expect(batch.results.single.response.status, ProviderResultStatus.cancelled);
    expect(observedCancel.isCompleted, isTrue);
  });

  test('provider failures never expose raw exception details', () async {
    final registry = ProviderRegistry()
      ..register(FakeProvider(
        descriptor: descriptor('unsafe-error'),
        handler: (query, token) async => throw Exception(
          'https://user:secret@example.org/path?token=should-not-escape',
        ),
      ));

    final batch = await ProviderCoordinator(registry).search('series');

    expect(batch.results.single.response.status, ProviderResultStatus.failed);
    expect(batch.results.single.response.message, isNot(contains('secret')));
    expect(batch.results.single.response.message, isNot(contains('should-not-escape')));
    expect(batch.results.single.response.message, isNot(contains('example.org')));
  });

}
