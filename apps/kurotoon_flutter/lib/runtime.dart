import 'package:kurotoon_core/kurotoon_core.dart';
import 'storage/kurotoon_database.dart';

/// Composition root for application services. The visual shell deliberately
/// stays out of this file so domain rules can be tested without a widget tree.
class KurotoonRuntime {
  KurotoonRuntime({
    ProviderRegistry? providers,
    StorageBudget? storageBudget,
    ReaderTimeline? readerTimeline,
    this.database,
  })  : providers = providers ?? _createDefaultProviders(),
        storageBudget = storageBudget ?? StorageBudget(),
        readerTimeline = readerTimeline ?? const ReaderTimeline();

  static Future<KurotoonRuntime> initialize({String? databasePath}) async {
    final database = await KurotoonDatabase.open(databasePath: databasePath);
    final runtime = KurotoonRuntime(database: database);
    await runtime.restoreProviderSettings();
    return runtime;
  }

  static ProviderRegistry _createDefaultProviders() => ProviderRegistry()
    ..register(MangaDexMultimediaProvider());

  final KurotoonDatabase? database;

  Future<void> restoreProviderSettings() async {
    final store = database;
    if (store == null) return;
    for (final provider in providers.all) {
      final saved = await store.getProviderEnabled(provider.descriptor.id);
      if (saved != null) providers.setEnabled(provider.descriptor.id, saved);
    }
  }

  Future<void> setProviderEnabled(String providerId, bool enabled) async {
    providers.setEnabled(providerId, enabled);
    await database?.setProviderEnabled(providerId, enabled);
  }

  Future<void> dispose() async {
    providers.dispose();
    await database?.close();
  }

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
