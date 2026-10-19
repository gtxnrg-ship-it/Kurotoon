import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kurotoon_core/kurotoon_core.dart';
import 'services/extension_repository_service.dart';
import 'services/reading_workflow_service.dart';
import 'storage/cache_storage_service.dart';
import 'storage/kurotoon_database.dart';
import 'storage/voice_pack_storage_service.dart';

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

  static final Uri officialRepositoryIndexUri = Uri.parse(
    'https://raw.githubusercontent.com/gtxnrg-ship-it/Kurotoon/main/catalog/official/index.json',
  );

  static Future<KurotoonRuntime> initialize({String? databasePath}) async {
    final database = await KurotoonDatabase.open(databasePath: databasePath);
    await _ensureOfficialRepository(database);
    final runtime = KurotoonRuntime(database: database);
    await runtime.restoreProviderSettings();
    return runtime;
  }

  /// Seeds the code-free official repository once. Existing user repositories
  /// and an existing official entry are never overwritten during app startup.
  static Future<void> _ensureOfficialRepository(KurotoonDatabase database) async {
    final repositories = await database.loadExtensionRepositories();
    if (repositories.any((row) => row['id'] == 'org.kurotoon.official')) return;
    await database.saveExtensionRepository(
      ExtensionRepository(
        id: 'org.kurotoon.official',
        name: 'KuroToon Official Starter Repository',
        indexUri: officialRepositoryIndexUri,
        description: 'Curated, code-free JSON extensions maintained for KuroToon.',
        website: Uri.parse('https://github.com/gtxnrg-ship-it/Kurotoon'),
        trust: RepositoryTrust.builtIn,
      ),
    );
  }

  static ProviderRegistry _createDefaultProviders() => ProviderRegistry()
    ..register(MangaDexMultimediaProvider());

  final KurotoonDatabase? database;
  ExtensionRepositoryService? _extensionRepositoryService;
  ReadingWorkflowService? _readingWorkflowService;
  Future<CacheStorageService>? _cacheStorageFuture;
  VoicePackStorageService? _voicePackStorageService;
  bool _disposing = false;
  final Map<String, String> extensionLoadErrors = {};

  /// Lazily opens the filesystem-backed cache manager. All cache writes share
  /// the same storage budget and persistent metadata database.
  Future<CacheStorageService> get cacheStorage {
    final store = database;
    if (store == null) {
      return Future.error(StateError('Persistent storage is required for cache management.'));
    }
    return _cacheStorageFuture ??= CacheStorageService.create(
      database: store,
      budget: storageBudget,
    );
  }

  ExtensionRepositoryService? get extensionRepositories {
    final store = database;
    if (store == null) return null;
    return _extensionRepositoryService ??= ExtensionRepositoryService(database: store);
  }

  /// The shared workflow layer for catalog admission, chapters, reader manifests,
  /// local library membership, and durable reading progress.
  ReadingWorkflowService get readingWorkflow {
    final store = database;
    if (store == null) {
      throw StateError('Persistent storage is required for reading workflows.');
    }
    return _readingWorkflowService ??= ReadingWorkflowService(
      database: store,
      providers: providers,
      healthTracker: providerHealth,
    );
  }

  VoicePackStorageService? get voicePacks {
    final store = database;
    if (store == null) return null;
    return _voicePackStorageService ??= VoicePackStorageService(database: store);
  }

  Future<void> restoreProviderSettings() async {
    final store = database;
    if (store == null) return;
    for (final provider in providers.all) {
      final saved = await store.getProviderEnabled(provider.descriptor.id);
      if (saved != null) providers.setEnabled(provider.descriptor.id, saved);
    }
    await loadInstalledExtensions();
    for (final provider in providers.all) {
      final savedHealth = await store.getSetting<Map<String, Object?>>(
        'provider.health.' + provider.descriptor.id,
      );
      if (savedHealth != null) providerHealth.restoreFromJson(provider.descriptor.id, savedHealth);
    }
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
        if (!await service.isSafeInstalledManifestPath(extensionId: id, manifestPath: path)) {
          throw const FormatException('Installed manifest path is outside the managed extension directory.');
        }
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

  Future<ExtensionRepositoryIndex> addExtensionRepository(
    String url, {
    String? expectedPreviewDigest,
  }) async {
    final service = extensionRepositories;
    if (service == null) throw StateError('Persistent storage is required to add repositories.');
    return service.addRepository(url, expectedPreviewDigest: expectedPreviewDigest);
  }

  Future<RepositoryPreview> handleAddRepositoryLink(Uri link) async {
    final indexUri = AddRepositoryLink.parse(link);
    return previewExtensionRepository(indexUri.toString());
  }

  Future<ExtensionRepositoryIndex> loadExtensionRepositoryIndex(String repositoryId) async {
    final service = extensionRepositories;
    if (service == null) throw StateError('Persistent storage is required to browse repositories.');
    return service.loadRepositoryIndex(repositoryId);
  }

  Future<String> installExtension({
    required String extensionId,
    required String repositoryId,
  }) async {
    final service = extensionRepositories;
    if (service == null) throw StateError('Persistent storage is required to install extensions.');
    final installPath = await service.installExtensionById(
      extensionId: extensionId,
      repositoryId: repositoryId,
    );
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
    _disposing = true;
    providers.dispose();
    _extensionRepositoryService?.dispose();
    _voicePackStorageService?.dispose();
    final pendingCache = _cacheStorageFuture;
    if (pendingCache != null) {
      try {
        await (await pendingCache).dispose();
      } on Object {
        // Database shutdown still needs to proceed if cache initialization failed.
      }
    }
    await database?.close();
  }

  final ProviderRegistry providers;
  final StorageBudget storageBudget;
  final ReaderTimeline readerTimeline;
  late final ProviderHealthTracker providerHealth = ProviderHealthTracker(onChanged: _persistProviderHealth);

  void _persistProviderHealth(ProviderHealthSnapshot snapshot) {
    final store = database;
    if (_disposing || store == null) return;
    unawaited(
      store.setSetting('provider.health.' + snapshot.providerId, snapshot.toJson()).catchError(
        (Object _) {},
      ),
    );
  }

  ProviderCoordinator createSearchCoordinator({
    int maxConcurrentProviders = 4,
    Duration providerTimeout = const Duration(seconds: 8),
  }) =>
      ProviderCoordinator(
        providers,
        maxConcurrentProviders: maxConcurrentProviders,
        providerTimeout: providerTimeout,
        healthTracker: providerHealth,
      );
}
