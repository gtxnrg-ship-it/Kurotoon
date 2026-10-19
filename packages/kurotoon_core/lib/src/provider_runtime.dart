import 'dart:async';

import 'cancellation.dart';
import 'catalog_entities.dart';
import 'models.dart';

abstract interface class DisposableProvider {
  void dispose();
}

abstract interface class SourceProvider {
  ProviderDescriptor get descriptor;

  Future<ProviderResponse<List<WorkCandidate>>> search(
    String query, {
    required CancellationToken cancellationToken,
  });
}

abstract interface class SeriesProvider implements SourceProvider {
  Future<ProviderResponse<WorkCandidate>> getSeries(
    String seriesId, {
    required CancellationToken cancellationToken,
  });
}

abstract interface class ChapterFeedProvider implements SourceProvider {
  Future<ProviderResponse<List<ChapterUnit>>> getChapters(
    String seriesId, {
    required CancellationToken cancellationToken,
    List<String> translatedLanguages = const ['en'],
    int limit = 100,
    int offset = 0,
  });
}

abstract interface class CreatorWorksProvider implements SourceProvider {
  Future<ProviderResponse<List<WorkCandidate>>> getCreatorWorks(
    String creatorId, {
    required CancellationToken cancellationToken,
    int limit = 100,
    int offset = 0,
  });
}

abstract interface class ReaderPagesProvider implements SourceProvider {
  Future<ProviderResponse<ReaderPageManifest>> getPages(
    String chapterId, {
    required CancellationToken cancellationToken,
    bool dataSaver = false,
  });
}

class ProviderRegistry {
  final Map<String, SourceProvider> _providers = {};
  final Map<String, bool> _enabled = {};

  List<SourceProvider> get all => List.unmodifiable(_providers.values);

  List<SourceProvider> get enabled => List.unmodifiable(
        _providers.values.where((provider) => _enabled[provider.descriptor.id] == true),
      );

  void register(SourceProvider provider) {
    final id = provider.descriptor.id;
    if (_providers.containsKey(id)) {
      throw StateError('Provider id already registered: $id');
    }
    _providers[id] = provider;
    _enabled[id] = provider.descriptor.enabledByDefault;
  }

  bool isEnabled(String id) => _enabled[id] == true;

  void setEnabled(String id, bool enabled) {
    if (!_providers.containsKey(id)) throw ArgumentError.value(id, 'id', 'Unknown provider');
    _enabled[id] = enabled;
  }

  void dispose() {
    for (final provider in _providers.values) {
      if (provider is DisposableProvider) (provider as DisposableProvider).dispose();
    }
    _providers.clear();
    _enabled.clear();
  }

  void removeCommunityProvider(String id) {
    final provider = _providers[id];
    if (provider == null) throw ArgumentError.value(id, 'id', 'Unknown provider');
    if (provider.descriptor.isBuiltIn) {
      throw StateError('Built-in providers can be disabled, but not removed.');
    }
    _providers.remove(id);
    _enabled.remove(id);
  }
}

class ProviderSearchResult {
  const ProviderSearchResult({
    required this.providerId,
    required this.response,
    required this.elapsed,
  });

  final String providerId;
  final ProviderResponse<List<WorkCandidate>> response;
  final Duration elapsed;
}

class SearchBatch {
  SearchBatch({required List<ProviderSearchResult> results, required this.cancelled})
      : results = List.unmodifiable(results);

  final List<ProviderSearchResult> results;
  final bool cancelled;

  List<WorkCandidate> get candidates {
    final unique = <String, WorkCandidate>{};
    for (final result in results) {
      for (final candidate in result.response.data ?? const <WorkCandidate>[]) {
        unique.putIfAbsent(candidate.listingKey, () => candidate);
      }
    }
    return List.unmodifiable(unique.values);
  }

  bool get hasPartialFailures => results.any(
        (result) => result.response.status != ProviderResultStatus.success &&
            result.response.status != ProviderResultStatus.partial,
      );
}

enum ProviderHealthState { healthy, degraded, coolingDown }

class ProviderHealthSnapshot {
  const ProviderHealthSnapshot({
    required this.providerId,
    required this.state,
    required this.consecutiveFailures,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.cooldownUntil,
    this.lastStatus,
    this.lastMessage,
  });

  final String providerId;
  final ProviderHealthState state;
  final int consecutiveFailures;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final DateTime? cooldownUntil;
  final ProviderResultStatus? lastStatus;
  final String? lastMessage;
}

/// In-memory per-provider circuit breaker. It backs off noisy or failing
/// sources without hiding their status from the caller. Success resets the
/// consecutive-failure streak; cancellation and unsupported operations do not
/// count as source failures.
class ProviderHealthTracker {
  ProviderHealthTracker({
    DateTime Function()? clock,
    this.failureThreshold = 2,
    this.baseCooldown = const Duration(seconds: 15),
    this.maxCooldown = const Duration(minutes: 5),
  }) : _clock = clock ?? DateTime.now {
    if (failureThreshold < 1) {
      throw ArgumentError.value(failureThreshold, 'failureThreshold');
    }
    if (baseCooldown <= Duration.zero || maxCooldown < baseCooldown) {
      throw ArgumentError('Cooldowns must be positive and maxCooldown >= baseCooldown.');
    }
  }

  final DateTime Function() _clock;
  final int failureThreshold;
  final Duration baseCooldown;
  final Duration maxCooldown;
  final Map<String, _ProviderHealthRecord> _records = {};

  ProviderHealthSnapshot snapshotFor(String providerId) {
    final record = _records[providerId];
    final now = _clock();
    final cooling = record?.cooldownUntil?.isAfter(now) ?? false;
    final state = cooling
        ? ProviderHealthState.coolingDown
        : (record?.consecutiveFailures ?? 0) > 0
            ? ProviderHealthState.degraded
            : ProviderHealthState.healthy;
    return ProviderHealthSnapshot(
      providerId: providerId,
      state: state,
      consecutiveFailures: record?.consecutiveFailures ?? 0,
      lastSuccessAt: record?.lastSuccessAt,
      lastFailureAt: record?.lastFailureAt,
      cooldownUntil: record?.cooldownUntil,
      lastStatus: record?.lastStatus,
      lastMessage: record?.lastMessage,
    );
  }

  Duration? remainingCooldown(String providerId) {
    final until = _records[providerId]?.cooldownUntil;
    if (until == null) return null;
    final remaining = until.difference(_clock());
    return remaining > Duration.zero ? remaining : null;
  }

  void record(String providerId, ProviderResponse<Object?> response) {
    final record = _records.putIfAbsent(providerId, _ProviderHealthRecord.new);
    record.lastStatus = response.status;
    record.lastMessage = response.message;

    if (response.status == ProviderResultStatus.success ||
        response.status == ProviderResultStatus.partial) {
      record.consecutiveFailures = 0;
      record.lastSuccessAt = _clock();
      record.cooldownUntil = null;
      return;
    }

    if (response.status == ProviderResultStatus.cancelled ||
        response.status == ProviderResultStatus.disabled ||
        response.status == ProviderResultStatus.unsupported) {
      return;
    }

    if (response.status != ProviderResultStatus.failed &&
        response.status != ProviderResultStatus.timedOut &&
        response.status != ProviderResultStatus.rateLimited &&
        response.status != ProviderResultStatus.blocked) {
      return;
    }

    final now = _clock();
    record.consecutiveFailures++;
    record.lastFailureAt = now;
    if (response.status == ProviderResultStatus.rateLimited) {
      final requested = response.retryAfter;
      final delay = requested != null && requested > Duration.zero
          ? requested
          : _cooldownFor(record.consecutiveFailures);
      record.cooldownUntil = now.add(delay);
    } else if (response.status == ProviderResultStatus.blocked) {
      record.cooldownUntil = now.add(baseCooldown);
    } else if (record.consecutiveFailures >= failureThreshold) {
      record.cooldownUntil = now.add(_cooldownFor(record.consecutiveFailures));
    }
  }

  Duration _cooldownFor(int failures) {
    final exponent = (failures - failureThreshold).clamp(0, 30);
    final delay = baseCooldown * (1 << exponent);
    return delay > maxCooldown ? maxCooldown : delay;
  }

  void reset(String providerId) => _records.remove(providerId);
}

class _ProviderHealthRecord {
  int consecutiveFailures = 0;
  DateTime? lastSuccessAt;
  DateTime? lastFailureAt;
  DateTime? cooldownUntil;
  ProviderResultStatus? lastStatus;
  String? lastMessage;
}

class ProviderCoordinator {
  ProviderCoordinator(
    this.registry, {
    this.maxConcurrentProviders = 4,
    this.providerTimeout = const Duration(seconds: 8),
    ProviderHealthTracker? healthTracker,
  }) : healthTracker = healthTracker ?? ProviderHealthTracker() {
    if (maxConcurrentProviders < 1) {
      throw ArgumentError.value(maxConcurrentProviders, 'maxConcurrentProviders');
    }
    if (providerTimeout <= Duration.zero) {
      throw ArgumentError.value(providerTimeout, 'providerTimeout');
    }
  }

  final ProviderRegistry registry;
  final int maxConcurrentProviders;
  final Duration providerTimeout;
  final ProviderHealthTracker healthTracker;

  Future<SearchBatch> search(
    String query, {
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken();
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return SearchBatch(results: const [], cancelled: token.isCancelled);
    }

    final providers = registry.enabled
        .where((provider) => provider.descriptor.supports(ProviderCapability.search))
        .toList(growable: false);
    final results = List<ProviderSearchResult?>.filled(providers.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        if (token.isCancelled) return;
        final index = nextIndex++;
        if (index >= providers.length) return;
        results[index] = await _searchOne(providers[index], normalizedQuery, token);
      }
    }

    final workerCount = providers.length < maxConcurrentProviders
        ? providers.length
        : maxConcurrentProviders;
    await Future.wait(List.generate(workerCount, (_) => worker()));

    final completed = results.whereType<ProviderSearchResult>().toList(growable: false);
    return SearchBatch(results: completed, cancelled: token.isCancelled);
  }

  Future<ProviderSearchResult> _searchOne(
    SourceProvider provider,
    String query,
    CancellationToken parent,
  ) async {
    final started = DateTime.now();
    final cooldown = healthTracker.remainingCooldown(provider.descriptor.id);
    if (cooldown != null) {
      return ProviderSearchResult(
        providerId: provider.descriptor.id,
        response: ProviderResponse<List<WorkCandidate>>(
          status: ProviderResultStatus.rateLimited,
          message: 'Provider temporarily paused after repeated failures',
          retryAfter: cooldown,
        ),
        elapsed: Duration.zero,
      );
    }
    final child = CancellationToken();
    final detach = parent.onCancel((reason) => child.cancel(reason));
    try {
      child.throwIfCancelled();
      final response = await provider
          .search(query, cancellationToken: child)
          .timeout(providerTimeout, onTimeout: () {
        child.cancel('Provider request timed out');
        return const ProviderResponse<List<WorkCandidate>>(
          status: ProviderResultStatus.timedOut,
          message: 'Provider exceeded its request time budget',
        );
      });
      healthTracker.record(provider.descriptor.id, response);
      return ProviderSearchResult(
        providerId: provider.descriptor.id,
        response: response,
        elapsed: DateTime.now().difference(started),
      );
    } on OperationCancelled catch (error) {
      final response = ProviderResponse<List<WorkCandidate>>(
        status: ProviderResultStatus.cancelled,
        message: error.reason,
      );
      healthTracker.record(provider.descriptor.id, response);
      return ProviderSearchResult(
        providerId: provider.descriptor.id,
        response: response,
        elapsed: DateTime.now().difference(started),
      );
    } catch (error) {
      final response = ProviderResponse<List<WorkCandidate>>(
        status: ProviderResultStatus.failed,
        message: _safeError(error),
      );
      healthTracker.record(provider.descriptor.id, response);
      return ProviderSearchResult(
        providerId: provider.descriptor.id,
        response: response,
        elapsed: DateTime.now().difference(started),
      );
    } finally {
      detach();
    }
  }

  String _safeError(Object error) {
    // Do not leak credentials, request bodies, or provider URLs into UI-facing logs.
    final message = error.runtimeType.toString();
    return 'Provider request failed ($message)';
  }
}
