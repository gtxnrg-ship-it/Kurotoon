import 'dart:convert';
import 'dart:io';

import 'package:kurotoon_core/kurotoon_core.dart';
import 'services/extension_repository_service.dart';
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
  ExtensionRepositoryService? _extensionRepositoryService;
  final Map<String, String> extensionLoadErrors = {};

  ExtensionRepositoryService? get extensionRepositories {
    final store = database;
    if (store == null) return null;
    return _extensionRepositoryService ??= ExtensionRepositoryService(database: store);
  }

  Future<void> restoreProviderSettings() async {
    final store = database;
    if (store == null) return;
    for (final provider in providers.all) {
      final saved = await store.getProviderEnabled(provider.descriptor.id);
      if (saved != null) providers.setEnabled(provider.descriptor.id, saved);
    }
    await loadInstalledExtensions();
  }

  Future<void> loadInstalledExtensions() async {
    final store = database;
    final service = extensionRepositories;
    if (store == null || service == null) return;
    extensionLoadErrors.clear();
    final rows = await store.loadInstalledExtensions();
    for (final row in rows) {
      final id = row['extension_id'] as String;
      try {
        final path = row['install_path'];
        if (path is! String) throw const FormatException('Installed manifest path is missing.');
        final file = File(path);
        if (!await file.exists()) throw const FormatException('Installed manifest file is missing.');
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) throw const FormatException('Installed manifest is not a JSON object.');
        final manifest = parseDeclarativeExtensionManifest(Map<String, Object?>.from(decoded));
        if (manifest.id != id) throw const FormatException('Installed manifest id does not match its record.');
        final existing = providers.all.where((provider) => provider.descriptor.id == id);
        if (existing.any((provider) => provider.descriptor.isBuiltIn)) {
          throw StateError('An extension cannot replace a built-in provider.');
        }
        if (existing.isNotEmpty) providers.removeCommunityProvider(id);
        providers.register(DeclarativeJsonProvider(manifest: manifest, fetcher: service));
        providers.setEnabled(id, row['enabled'] == 1);
      } on Object catch (error) {
        extensionLoadErrors[id] = error.toString();
      }
    }
  }

  Future<RepositoryPreview> previewExtensionRepository(String url) async {
    final service = extensionRepositories;
    if (service == null) throw StateError('Persistent storage is required to preview repositories.');
    return service.previewRepository(url);
  }

  Future<ExtensionRepositoryIndex> addExtensionRepository(String url) async {
    final service = extensionRepositories;
    if (service == null) throw StateError('Persistent storage is required to add repositories.');
    return service.addRepository(url);
  }

  Future<ExtensionRepositoryIndex> handleAddRepositoryLink(Uri link) async {
    final indexUri = AddRepositoryLink.parse(link);
    return addExtensionRepository(indexUri.toString());
  }

  Future<String> installExtension({
    required ExtensionPackageEntry entry,
    required String repositoryId,
  }) async {
    final service = extensionRepositories;
    if (service == null) throw StateError('Persistent storage is required to install extensions.');
    final installPath = await service.installDeclarativeExtension(entry: entry, repositoryId: repositoryId);
    await loadInstalledExtensions();
    return installPath;
  }

  Future<void> uninstallExtension(String extensionId) async {
    final service = extensionRepositories;
    if (service == null) throw StateError('Persistent storage is required to uninstall extensions.');
    await service.uninstallExtension(extensionId);
    final provider = providers.all.where((item) => item.descriptor.id == extensionId);
    if (provider.isNotEmpty) providers.removeCommunityProvider(extensionId);
    extensionLoadErrors.remove(extensionId);
  }

  Future<void> setExtensionEnabled(String extensionId, bool enabled) async {
    final store = database;
    if (store == null) throw StateError('Persistent storage is required to change extension state.');
    if (!providers.all.any((provider) => provider.descriptor.id == extensionId)) {
      throw ArgumentError.value(extensionId, 'extensionId', 'Extension is not loaded.');
    }
    await store.setExtensionEnabled(extensionId, enabled);
    providers.setEnabled(extensionId, enabled);
  }

  Future<void> setProviderEnabled(String providerId, bool enabled) async {
    providers.setEnabled(providerId, enabled);
    await database?.setProviderEnabled(providerId, enabled);
  }

  Future<void> dispose() async {
    providers.dispose();
    _extensionRepositoryService?.dispose();
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
