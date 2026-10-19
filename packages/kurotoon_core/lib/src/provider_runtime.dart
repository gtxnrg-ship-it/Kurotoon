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

class ProviderCoordinator {
  ProviderCoordinator(
    this.registry, {
    this.maxConcurrentProviders = 4,
    this.providerTimeout = const Duration(seconds: 8),
  }) {
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
      return ProviderSearchResult(
        providerId: provider.descriptor.id,
        response: response,
        elapsed: DateTime.now().difference(started),
      );
    } on OperationCancelled catch (error) {
      return ProviderSearchResult(
        providerId: provider.descriptor.id,
        response: ProviderResponse(status: ProviderResultStatus.cancelled, message: error.reason),
        elapsed: DateTime.now().difference(started),
      );
    } catch (error) {
      return ProviderSearchResult(
        providerId: provider.descriptor.id,
        response: ProviderResponse(status: ProviderResultStatus.failed, message: _safeError(error)),
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
