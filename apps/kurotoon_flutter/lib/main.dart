import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kurotoon_core/kurotoon_core.dart';

import 'runtime.dart';
import 'services/catalog_workflow_service.dart';
import 'ui/library_page.dart';
import 'ui/repository_management_page.dart';
import 'ui/series_detail_page.dart';
import 'ui/shop_page.dart';
import 'ui/storage_management_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KuroToonApp());
}

const _ink = Color(0xFF080B18);
const _panel = Color(0xFF11182B);
const _violet = Color(0xFF9D8CFF);
const _cyan = Color(0xFF6EE7F9);

class KuroToonApp extends StatefulWidget {
  const KuroToonApp({super.key});

  @override
  State<KuroToonApp> createState() => _KuroToonAppState();
}

class _KuroToonAppState extends State<KuroToonApp> {
  late final Future<KurotoonRuntime> _runtime = KurotoonRuntime.initialize();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kurotoon',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _ink,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _violet,
          brightness: Brightness.dark,
          surface: _panel,
        ),
        useMaterial3: true,
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xEE0B1020),
          indicatorColor: Color(0x443D5A99),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.055),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      home: FutureBuilder<KurotoonRuntime>(
        future: _runtime,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StartupError(message: snapshot.error.toString());
          }
          if (!snapshot.hasData) {
            return const _StartupScreen();
          }
          return _KuroToonShell(runtime: snapshot.data!);
        },
      ),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) => const _GalaxyScaffold(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BrandMark(size: 76),
              SizedBox(height: 22),
              Text('KUROTOON', style: TextStyle(letterSpacing: 5, fontWeight: FontWeight.w800, fontSize: 19)),
              SizedBox(height: 12),
              SizedBox(width: 100, child: LinearProgressIndicator(minHeight: 2)),
              SizedBox(height: 12),
              Text('Waking up the galaxy…', style: TextStyle(color: Colors.white60)),
            ],
          ),
        ),
      );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => _GalaxyScaffold(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 48, color: _cyan),
                const SizedBox(height: 18),
                const Text('Kurotoon could not start', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('The local app database could not be opened. Your library has not been changed.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                Text(message, maxLines: 4, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white38)),
              ],
            ),
          ),
        ),
      );
}

class _KuroToonShell extends StatefulWidget {
  const _KuroToonShell({required this.runtime});
  final KurotoonRuntime runtime;

  @override
  State<_KuroToonShell> createState() => _KuroToonShellState();
}

class _KuroToonShellState extends State<_KuroToonShell> {
  int _selected = 0;
  bool _motionEnabled = true;

  @override
  void initState() {
    super.initState();
    _restoreMotionPreference();
  }

  Future<void> _restoreMotionPreference() async {
    try {
      final saved = await widget.runtime.database?.getSetting<bool>('ui.motion_enabled');
      if (mounted && saved != null) setState(() => _motionEnabled = saved);
    } on Object {
      // Keep the default if the optional preference cannot be read.
    }
  }

  Future<void> _setMotionEnabled(bool enabled) async {
    setState(() => _motionEnabled = enabled);
    try {
      await widget.runtime.database?.setSetting('ui.motion_enabled', enabled);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Motion changed for this session, but the preference could not be saved.')),
        );
      }
    }
  }

  @override
  void dispose() {
    widget.runtime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomePage(onBrowse: () => setState(() => _selected = 1)),
      _BrowserPage(runtime: widget.runtime),
      const ShopPage(),
      LibraryPage(runtime: widget.runtime),
      _MePage(runtime: widget.runtime, motionEnabled: _motionEnabled, onMotionChanged: _setMotionEnabled),
    ];
    return Scaffold(
      extendBody: true,
      body: _GalaxyScaffold(
        animated: _motionEnabled,
        child: SafeArea(
          bottom: false,
          child: IndexedStack(index: _selected, children: pages),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected,
        onDestinationSelected: (index) => setState(() => _selected = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.travel_explore_rounded), label: 'Browser'),
          NavigationDestination(icon: Icon(Icons.storefront_rounded), label: 'Shop'),
          NavigationDestination(icon: Icon(Icons.bookmarks_rounded), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Me'),
        ],
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({required this.onBrowse});
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 130),
        children: [
          Row(
            children: [
              const _BrandMark(size: 42),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('KUROTOON', style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w900, fontSize: 16)),
                    Text('A universe between the panels', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Open Browser',
                onPressed: onBrowse,
                icon: const Icon(Icons.search_rounded),
                style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.07)),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xCC273C72), Color(0xCC17162F), Color(0xAA101A2B)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('YOUR NEXT WORLD\nIS OUT THERE.',
                    style: TextStyle(fontSize: 27, height: 1.12, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 12),
                const Text('Explore stories across sources. Build a library that feels like yours.',
                    style: TextStyle(height: 1.45, color: Colors.white70)),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onBrowse,
                  icon: const Icon(Icons.explore_rounded),
                  label: const Text('Explore the universe'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const _SectionHeading(title: 'Built for your worlds', subtitle: 'A native-first foundation, growing feature by feature'),
          const SizedBox(height: 14),
          const _FeatureTile(
            icon: Icons.hub_rounded,
            title: 'Multiple sources',
            subtitle: 'Repository-first extensions, installed one at a time with a review step.',
            tint: _cyan,
          ),
          const SizedBox(height: 10),
          const _FeatureTile(
            icon: Icons.auto_awesome_rounded,
            title: 'A living Galaxy',
            subtitle: 'Ambient motion with adaptive effects designed to respect your device.',
            tint: _violet,
          ),
          const SizedBox(height: 10),
          const _FeatureTile(
            icon: Icons.offline_pin_rounded,
            title: 'Your data stays yours',
            subtitle: 'Your library and reading progress stay local; disposable cache is managed in Me → Storage & privacy.',
            tint: Color(0xFFFFC58A),
          ),
          const SizedBox(height: 24),
          Text('Live discovery needs an internet connection. Your library and saved reading positions remain on this device.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.42), fontSize: 11)),
        ],
      );
}

class _BrowserPage extends StatefulWidget {
  const _BrowserPage({required this.runtime});
  final KurotoonRuntime runtime;

  @override
  State<_BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<_BrowserPage> {
  final _controller = TextEditingController();
  CatalogSearchOutcome? _outcome;
  bool _loading = false;
  String? _error;
  WorkFormat? _formatFilter;
  String? _sourceFilter;
  String? _languageFilter;

  List<CatalogEntry> get _visibleEntries {
    final entries = (_outcome?.entries ?? const <CatalogEntry>[]).where((entry) {
      if (_formatFilter != null && entry.work.format != _formatFilter) return false;
      if (_sourceFilter != null && !entry.providerIds.contains(_sourceFilter)) return false;
      if (_languageFilter != null &&
          !entry.listings.any((listing) => listing.language?.toLowerCase() == _languageFilter)) {
        return false;
      }
      return true;
    }).toList();
    final query = WorkIdentityMatcher.normalizeTitle(_controller.text);
    entries.sort((left, right) {
      int relevance(CatalogEntry entry) {
        final title = WorkIdentityMatcher.normalizeTitle(entry.work.title);
        if (title == query) return 0;
        if (title.startsWith(query)) return 1;
        if (entry.work.alternateTitles.any((alias) => WorkIdentityMatcher.normalizeTitle(alias) == query)) return 2;
        return 3;
      }
      final order = relevance(left).compareTo(relevance(right));
      return order != 0 ? order : left.work.title.toLowerCase().compareTo(right.work.title.toLowerCase());
    });
    return List.unmodifiable(entries);
  }

  String _formatLabel(WorkFormat format) => switch (format) {
        WorkFormat.manga => 'Manga',
        WorkFormat.manhwa => 'Manhwa',
        WorkFormat.manhua => 'Manhua',
        WorkFormat.webtoon => 'Webtoon',
        WorkFormat.comic => 'Comic',
        WorkFormat.novel => 'Novel',
        WorkFormat.oneShot => 'One-shot',
        WorkFormat.unknown => 'Other',
      };

  String _sourceName(String id) {
    final matches = widget.runtime.providers.all.where((provider) => provider.descriptor.id == id);
    return matches.isEmpty ? id : matches.first.descriptor.name;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _outcome = null;
    });
    try {
      final workflow = widget.runtime.catalogWorkflow;
      if (workflow == null) throw StateError('Persistent catalog storage is unavailable.');
      final outcome = await workflow.searchAndCatalog(query);
      if (!mounted) return;
      setState(() => _outcome = outcome);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Search could not complete. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  WorkCandidate _candidateForEntry(CatalogEntry entry) {
    if (entry.listings.isEmpty) throw StateError('Catalog entry has no source listings.');
    final candidates = entry.listings.toList();
    candidates.sort((left, right) {
      int priority(WorkCandidate candidate) {
        final providers = widget.runtime.providers.all.where((item) => item.descriptor.id == candidate.providerId);
        if (providers.isEmpty) return 0;
        final provider = providers.first;
        final enabled = widget.runtime.providers.isEnabled(candidate.providerId);
        final chapters = provider is ChapterFeedProvider &&
            provider.descriptor.supports(ProviderCapability.chapters);
        final pages = provider is ReaderPagesProvider &&
            provider.descriptor.supports(ProviderCapability.pages);
        return (enabled ? 4 : 0) + (chapters ? 2 : 0) + (pages ? 1 : 0);
      }
      return priority(right).compareTo(priority(left));
    });
    final source = candidates.first;
    return WorkCandidate(
      providerId: source.providerId,
      externalId: source.externalId,
      title: entry.work.title,
      providerUrl: source.providerUrl,
      alternateTitles: entry.work.alternateTitles,
      creatorNames: entry.work.creatorNames,
      year: entry.work.year,
      format: entry.work.format,
      language: source.language,
      description: source.description,
      coverUrl: source.coverUrl,
      tags: source.tags,
    );
  }

  Future<void> _openSeries(WorkCandidate candidate) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SeriesDetailPage(runtime: widget.runtime, candidate: candidate),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 130),
        children: [
          const Text('BROWSER', style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w900, fontSize: 13, color: _cyan)),
          const SizedBox(height: 8),
          const Text('Find your next obsession.', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Search the sources currently connected to Kurotoon.',
              style: TextStyle(color: Colors.white60, height: 1.4)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    hintText: 'Title, alternate title…',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _loading ? null : _search,
                icon: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.arrow_forward_rounded),
                tooltip: 'Search',
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) _InlineNotice(icon: Icons.wifi_off_rounded, text: _error!),
          if (_outcome != null) ...[
            _SectionHeading(
              title: '${_visibleEntries.length} of ${_outcome!.entries.length} unified results',
              subtitle: _outcome!.batch.hasPartialFailures
                  ? 'Some sources did not respond. Results are merged where identity matching is safe.'
                  : 'Across ${widget.runtime.providers.enabled.length} enabled sources · duplicate listings grouped safely.',
            ),
            const SizedBox(height: 12),
            if (_outcome!.entries.isNotEmpty) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  ChoiceChip(
                    label: const Text('All formats'),
                    selected: _formatFilter == null,
                    onSelected: (_) => setState(() => _formatFilter = null),
                  ),
                  for (final format in WorkFormat.values.where((item) => item != WorkFormat.unknown)) ...[
                    const SizedBox(width: 7),
                    ChoiceChip(
                      label: Text(_formatLabel(format)),
                      selected: _formatFilter == format,
                      onSelected: (_) => setState(() => _formatFilter = _formatFilter == format ? null : format),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final sources = _outcome!.entries.expand((entry) => entry.providerIds).toSet().toList()..sort();
                final languages = _outcome!.entries.expand((entry) => entry.listings
                    .map((listing) => listing.language?.toLowerCase())
                    .whereType<String>()
                    .where((language) => language.isNotEmpty)).toSet().toList()..sort();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sources.length > 1) ...[
                      const Text('SOURCE', style: TextStyle(letterSpacing: 1.5, color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          ChoiceChip(label: const Text('All sources'), selected: _sourceFilter == null,
                            onSelected: (_) => setState(() => _sourceFilter = null)),
                          for (final source in sources) ...[
                            const SizedBox(width: 7),
                            ChoiceChip(label: Text(_sourceName(source)), selected: _sourceFilter == source,
                              onSelected: (_) => setState(() => _sourceFilter = _sourceFilter == source ? null : source)),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (languages.length > 1) ...[
                      const Text('LANGUAGE', style: TextStyle(letterSpacing: 1.5, color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          ChoiceChip(label: const Text('All languages'), selected: _languageFilter == null,
                            onSelected: (_) => setState(() => _languageFilter = null)),
                          for (final language in languages) ...[
                            const SizedBox(width: 7),
                            ChoiceChip(label: Text(language.toUpperCase()), selected: _languageFilter == language,
                              onSelected: (_) => setState(() => _languageFilter = _languageFilter == language ? null : language)),
                          ],
                        ]),
                      ),
                    ],
                  ],
                );
              }),
              const SizedBox(height: 12),
            ],
            if (_outcome!.entries.isEmpty)
              const _InlineNotice(icon: Icons.search_off_rounded, text: 'No results returned. Try another title or check the source connection.')
            else if (_visibleEntries.isEmpty)
              const _InlineNotice(icon: Icons.filter_alt_off_rounded, text: 'No results match these filters. Clear a filter or try another title.')
            else
              for (final entry in _visibleEntries) ...[
                _SearchResultTile(
                  candidate: _candidateForEntry(entry),
                  sourceLabels: entry.providerIds.map((id) {
                    final providers = widget.runtime.providers.all.where((provider) => provider.descriptor.id == id);
                    return providers.isEmpty ? id : providers.first.descriptor.name;
                  }).toList(growable: false),
                  onTap: () => _openSeries(_candidateForEntry(entry)),
                ),
                const SizedBox(height: 10),
              ],
          ],
          if (!_loading && _outcome == null && _error == null)
            const _InlineNotice(
              icon: Icons.public_rounded,
              text: 'Search uses live provider APIs. Results depend on source availability; Kurotoon does not host comic content.',
            ),
        ],
      );
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.candidate,
    required this.sourceLabels,
    required this.onTap,
  });
  final WorkCandidate candidate;
  final List<String> sourceLabels;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 76,
                height: 106,
                child: candidate.coverUrl == null
                    ? const ColoredBox(color: _panel, child: Icon(Icons.menu_book_rounded, color: Colors.white38))
                    : Image.network(
                        candidate.coverUrl.toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(color: _panel, child: Icon(Icons.broken_image_outlined)),
                      ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(candidate.title, maxLines: 3, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.25)),
                  const SizedBox(height: 8),
                  if (candidate.creatorNames.isNotEmpty)
                    Text(candidate.creatorNames.take(2).join(', '),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  if (candidate.tags.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(candidate.tags.take(3).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _cyan, fontSize: 11)),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    sourceLabels.length == 1
                        ? '1 SOURCE · ${sourceLabels.first}'
                        : '${sourceLabels.length} SOURCES · ${sourceLabels.take(3).join(' · ')}${sourceLabels.length > 3 ? ' · +' + (sourceLabels.length - 3).toString() : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(letterSpacing: .5, color: _violet, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text('View details'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _MePage extends StatefulWidget {
  const _MePage({required this.runtime, required this.motionEnabled, required this.onMotionChanged});
  final KurotoonRuntime runtime;
  final bool motionEnabled;
  final ValueChanged<bool> onMotionChanged;

  @override
  State<_MePage> createState() => _MePageState();
}

class _MePageState extends State<_MePage> {
  bool _mangadexEnabled = true;

  @override
  Widget build(BuildContext context) {
    final provider = widget.runtime.providers.all.where((p) => p.descriptor.id == 'mangadex');
    if (provider.isNotEmpty) _mangadexEnabled = widget.runtime.providers.isEnabled('mangadex');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 130),
      children: [
        const Text('ME', style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w900, fontSize: 13, color: _violet)),
        const SizedBox(height: 8),
        const Text('Your reading, your rules.', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        const _SectionHeading(title: 'Reading', subtitle: 'Sources, extensions, and reader preferences'),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          tileColor: Colors.white.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          secondary: const Icon(Icons.public_rounded, color: _cyan),
          title: const Text('MangaDex'),
          subtitle: const Text('Live API provider'),
          value: _mangadexEnabled,
          onChanged: (value) async {
            await widget.runtime.setProviderEnabled('mangadex', value);
            if (mounted) setState(() => _mangadexEnabled = value);
          },
        ),
        const SizedBox(height: 18),
        const _SectionHeading(title: 'Extensions & repositories', subtitle: 'Add catalogs and manage supported sources'),
        const _InlineNotice(
          icon: Icons.extension_rounded,
          text: 'Browse catalogs and manage compatible declarative extensions. Compiled extension APKs are not executed.',
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => RepositoryManagementPage(runtime: widget.runtime),
            ),
          ),
          icon: const Icon(Icons.settings_input_component_rounded),
          label: const Text('Manage repositories & extensions'),
          style: FilledButton.styleFrom(
            backgroundColor: _violet,
            foregroundColor: const Color(0xFF080B18),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 22),
        const _SectionHeading(title: 'Storage & privacy', subtitle: 'Manage disposable cache without touching your saved library or progress'),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => StorageManagementPage(runtime: widget.runtime),
            ),
          ),
          icon: const Icon(Icons.storage_rounded),
          label: const Text('Manage storage & cache'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _cyan,
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: BorderSide(color: _cyan.withValues(alpha: 0.35)),
          ),
        ),
        const SizedBox(height: 22),
        const _SectionHeading(title: 'Galaxy', subtitle: 'Motion preferences'),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          tileColor: Colors.white.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          secondary: const Icon(Icons.blur_on_rounded, color: _violet),
          title: const Text('Animated background'),
          subtitle: const Text('Saved on this device; turn it off to reduce background animation.'),
          value: widget.motionEnabled,
          onChanged: widget.onMotionChanged,
        ),
        const SizedBox(height: 22),
      ],
    );
  }
}

class _GalaxyScaffold extends StatefulWidget {
  const _GalaxyScaffold({required this.child, this.animated = true});
  final Widget child;
  final bool animated;

  @override
  State<_GalaxyScaffold> createState() => _GalaxyScaffoldState();
}

class _GalaxyScaffoldState extends State<_GalaxyScaffold> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 42),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animated) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _GalaxyScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animated == widget.animated) return;
    if (widget.animated) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => CustomPaint(
          painter: _GalaxyPainter(progress: widget.animated ? _controller.value : 0),
          child: child,
        ),
        child: widget.child,
      );
}

class _GalaxyPainter extends CustomPainter {
  const _GalaxyPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _ink);
    final glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 55);
    final phase = progress * math.pi * 2;
    glow.color = const Color(0xFF30246F).withValues(alpha: 0.34);
    canvas.drawCircle(Offset(size.width * (0.16 + 0.09 * math.sin(phase)), size.height * 0.18), size.width * 0.34, glow);
    glow.color = const Color(0xFF075B70).withValues(alpha: 0.24);
    canvas.drawCircle(Offset(size.width * (0.88 + 0.06 * math.cos(phase * 0.7)), size.height * 0.58), size.width * 0.32, glow);
    glow.color = const Color(0xFF34224F).withValues(alpha: 0.22);
    canvas.drawCircle(Offset(size.width * 0.48, size.height * (0.86 + 0.04 * math.sin(phase * 0.5))), size.width * 0.38, glow);

    final stars = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 100; i++) {
      final seed = i * 73.37 + 19.0;
      final x = ((math.sin(seed * 12.9898) * 43758.5453) % 1).abs() * size.width;
      final baseY = ((math.sin(seed * 78.233) * 12345.678) % 1).abs() * size.height;
      final y = (baseY + progress * (10 + (i % 17) * 2)) % size.height;
      final twinkle = 0.18 + 0.72 * ((math.sin(phase * (0.5 + (i % 5) * 0.1) + seed) + 1) / 2);
      stars.color = (i % 7 == 0 ? _cyan : Colors.white).withValues(alpha: twinkle);
      canvas.drawCircle(Offset(x, y), i % 11 == 0 ? 1.45 : 0.7 + (i % 3) * 0.22, stars);
    }
    final filament = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _violet.withValues(alpha: 0.09);
    final path = Path()
      ..moveTo(size.width * 0.08, size.height * 0.36)
      ..cubicTo(
        size.width * (0.2 + 0.02 * math.sin(phase)),
        size.height * 0.28,
        size.width * (0.72 + 0.04 * math.cos(phase)),
        size.height * 0.47,
        size.width * 0.95,
        size.height * 0.31,
      );
    canvas.drawPath(path, filament);
  }

  @override
  bool shouldRepaint(covariant _GalaxyPainter oldDelegate) => oldDelegate.progress != progress;
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [_cyan, _violet, Color(0xFF3B2B74)]),
          boxShadow: [BoxShadow(color: _violet.withValues(alpha: 0.22), blurRadius: 24, spreadRadius: 1)],
        ),
        child: Icon(Icons.auto_awesome_rounded, size: size * 0.48, color: const Color(0xFF080B18)),
      );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.35)),
        ],
      );
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.icon, required this.title, required this.subtitle, required this.tint});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
        ),
        child: Row(
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: tint),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: _cyan),
            const SizedBox(width: 11),
            Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 12))),
          ],
        ),
      );
}
