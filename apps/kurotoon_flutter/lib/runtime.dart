import 'package:kurotoon_core/kurotoon_core.dart';

/// Composition root for application services. The visual shell deliberately
/// stays out of this file so domain rules can be tested without a widget tree.
class KurotoonRuntime {
  KurotoonRuntime({
    ProviderRegistry? providers,
    StorageBudget? storageBudget,
    ReaderTimeline? readerTimeline,
  })  : providers = providers ?? _createDefaultProviders(),
        storageBudget = storageBudget ?? StorageBudget(),
        readerTimeline = readerTimeline ?? const ReaderTimeline();

  static ProviderRegistry _createDefaultProviders() => ProviderRegistry()
    ..register(MangaDexMultimediaProvider());

  void dispose() => providers.dispose();

  final ProviderRegistry providers;
  final StorageBudget storageBudget;
  final ReaderTimeline readerTimeline;

  ProviderCoordinator createSearchCoordinator({
    int maxConcurrentProviders = 4,
    Duration providerTimeout = const Duration(seconds: 8),
  }) =>
      ProviderCoordinator(
        providers,
        maxConcurrentProviders: maxConcurrentProviders,
        providerTimeout: providerTimeout,
      );
}
