import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:kurotoon_core/kurotoon_core.dart';

import 'runtime.dart';
import 'services/catalog_workflow_service.dart';
import 'services/reading_journey_service.dart';
import 'ui/library_page.dart';
import 'ui/reader_page.dart';
import 'ui/reader_display_preferences.dart';
import 'ui/galaxy_motion_policy.dart';
import 'ui/provider_diagnostics_page.dart';
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

class _KuroToonShellState extends State<_KuroToonShell> with WidgetsBindingObserver {
  int _selected = 0;
  bool _motionEnabled = true;
  bool _motionSaving = false;
  bool _appResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appResumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _restoreMotionPreference();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (_appResumed == resumed) return;
    setState(() => _appResumed = resumed);
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
    if (_motionSaving || enabled == _motionEnabled) return;
    setState(() => _motionSaving = true);
    try {
      final database = widget.runtime.database;
      if (database == null) throw StateError('Local settings are unavailable.');
      await database.setSetting('ui.motion_enabled', enabled);
    } on Object {
      if (!mounted) return;
      setState(() => _motionSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Motion preference could not be saved. The previous setting was kept.')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _motionEnabled = enabled;
      _motionSaving = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.runtime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animateGalaxy = shouldAnimateGalaxy(
      userEnabled: _motionEnabled,
      systemReducedMotion: MediaQuery.of(context).disableAnimations,
      appResumed: _appResumed,
    );
    final pages = [
      _HomePage(
        runtime: widget.runtime,
        isActive: _selected == 0,
        onBrowse: () => setState(() => _selected = 1),
        onLibrary: () => setState(() => _selected = 3),
      ),
      _BrowserPage(runtime: widget.runtime),
      const ShopPage(),
      LibraryPage(runtime: widget.runtime),
      _MePage(
        runtime: widget.runtime,
        motionEnabled: _motionEnabled,
        motionSaving: _motionSaving,
        onMotionChanged: _setMotionEnabled,
      ),
    ];
    return Scaffold(
      extendBody: true,
      body: _GalaxyScaffold(
        animated: animateGalaxy,
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

class _HomePage extends StatefulWidget {
  const _HomePage({
    required this.runtime,
    required this.isActive,
    required this.onBrowse,
    required this.onLibrary,
  });

  final KurotoonRuntime runtime;
  final bool isActive;
  final VoidCallback onBrowse;
  final VoidCallback onLibrary;

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  bool _loadingRecent = true;
  String? _recentError;
  List<RecentReadingEntry> _recent = const [];

  @override
  void initState() {
    super.initState();
    _reloadRecent();
  }

  @override
  void didUpdateWidget(covariant _HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // IndexedStack keeps Home mounted while the user reads from Browser or
    // Library. Refresh when Home becomes visible again so "Continue reading"
    // never shows the previous chapter after a reading session.
    if (!oldWidget.isActive && widget.isActive) _reloadRecent();
  }

  Future<void> _reloadRecent() async {
    if (!mounted) return;
    setState(() {
      _loadingRecent = true;
      _recentError = null;
    });
    try {
      final service = widget.runtime.readingJourney;
      if (service == null) throw StateError('Persistent reading history is unavailable.');
      final entries = await service.loadRecentReading(limit: 5);
      if (!mounted) return;
      setState(() {
        _recent = entries;
        _loadingRecent = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _recentError = 'Recent reading could not be loaded. Your saved progress has not been changed.';
        _loadingRecent = false;
      });
    }
  }

  Future<void> _resume(RecentReadingEntry entry) async {
    final target = entry.target;
    final chapter = target.chapter;
    if (!target.canResume || chapter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This saved chapter needs a source refresh before it can be resumed.')),
      );
      return;
    }
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ReaderPage(
            runtime: widget.runtime,
            workId: target.progress.workId,
            chapter: chapter,
          ),
        ),
      );
      if (mounted) await _reloadRecent();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not resume this chapter. Your reading history remains saved.')),
        );
      }
    }
  }

  Widget _continueReadingCard(RecentReadingEntry entry) {
    final title = entry.catalogEntry?.work.title ?? 'Unknown series';
    final chapter = entry.target.chapter;
    final chapterNumber = chapter?.chapterNumber;
    final chapterLabel = chapter == null
        ? 'Chapter list needs refresh'
        : (chapter.title ?? (chapterNumber == null ? 'Special chapter' : 'Chapter $chapterNumber'));
    final progress = entry.target.progress.fraction.clamp(0.0, 1.0).toDouble();
    final percent = (progress * 100).round();
    final listings = entry.catalogEntry?.listings ?? const <WorkCandidate>[];
    final Uri? cover = listings.isEmpty ? null : listings.first.coverUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.075)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _resume(entry),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 66,
                height: 92,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: cover == null
                      ? Container(
                          color: _panel,
                          child: const Icon(Icons.menu_book_rounded, color: _cyan, size: 28),
                        )
                      : Image.network(
                          cover.toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: _panel,
                            child: const Icon(Icons.menu_book_rounded, color: _cyan, size: 28),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      chapterLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 11),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(value: progress, minHeight: 4),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.target.canResume ? '$percent% through chapter' : 'Progress saved · source refresh needed',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54, fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Icon(
                          entry.target.canResume ? Icons.play_circle_outline_rounded : Icons.refresh_rounded,
                          color: _violet,
                          size: 22,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyRecentState() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_stories_rounded, color: _cyan, size: 28),
            const SizedBox(height: 10),
            const Text('Your next chapter starts here.', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            const Text(
              'Once you read a chapter, Kurotoon will keep your recent reading here—even if you later remove the series from your library.',
              style: TextStyle(color: Colors.white60, height: 1.45, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: widget.onBrowse,
              icon: const Icon(Icons.explore_rounded),
              label: const Text('Find a story'),
            ),
          ],
        ),
      );

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
                onPressed: widget.onBrowse,
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
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: widget.onBrowse,
                      icon: const Icon(Icons.explore_rounded),
                      label: const Text('Explore the universe'),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.onLibrary,
                      icon: const Icon(Icons.bookmarks_rounded),
                      label: const Text('Open my library'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const _SectionHeading(
            title: 'Continue reading',
            subtitle: 'Your most recent chapters, right where you left off',
          ),
          const SizedBox(height: 14),
          if (_loadingRecent) const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          ),
          if (_recentError != null) ...[
            _InlineNotice(icon: Icons.history_rounded, text: _recentError!),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _reloadRecent,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry history'),
              ),
            ),
          ],
          if (!_loadingRecent && _recentError == null && _recent.isEmpty) _emptyRecentState(),
          if (!_loadingRecent && _recentError == null)
            for (final entry in _recent) _continueReadingCard(entry),
          const SizedBox(height: 18),
          const _SectionHeading(title: 'Built for your worlds', subtitle: 'A native-first foundation, growing feature by feature'),
          const SizedBox(height: 14),
          const _FeatureTile(
            icon: Icons.hub_rounded,
            title: 'Source-ready by design',
            subtitle: 'MangaDex is the current live connector; compatible catalog repositories can be previewed safely.',
            tint: _cyan,
          ),
          const SizedBox(height: 10),
          const _FeatureTile(
            icon: Icons.auto_awesome_rounded,
            title: 'A living Galaxy',
            subtitle: 'Ambient galaxy effects, with a reduced-motion option in Me.',
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
  String _lastSubmittedQuery = '';
  List<String> _recentQueries = const [];
  bool _creatorMode = false;
  bool _creatorSearchPerformed = false;
  String _lastCreatorQuery = '';
  List<CreatorProfile> _creatorResults = const [];

  @override
  void initState() {
    super.initState();
    _restoreRecentQueries();
  }

  Future<void> _restoreRecentQueries() async {
    try {
      final saved = await widget.runtime.database?.getSetting<List<dynamic>>('browser.recent_queries');
      final seen = <String>{};
      final cleaned = <String>[];
      // Settings can outlive app versions; validate shape and cap before rendering.
      for (final item in saved ?? const <dynamic>[]) {
        if (item is! String) continue;
        final query = item.trim();
        if (query.isEmpty || !seen.add(query.toLowerCase())) continue;
        cleaned.add(query);
        if (cleaned.length == 6) break;
      }
      if (mounted) setState(() => _recentQueries = List.unmodifiable(cleaned));
    } on Object {
      // Search history is optional: corrupt/missing preferences must not block Browse.
    }
  }

  List<CatalogEntry> get _visibleEntries {
    final entries = (_outcome?.entries ?? const <CatalogEntry>[]).where((entry) {
      // A stale/orphaned catalog row must not reach _candidateForEntry, which
      // intentionally expects at least one source listing to open a series.
      if (entry.listings.isEmpty) return false;
      if (_formatFilter != null && entry.work.format != _formatFilter) return false;
      if (_sourceFilter != null && !entry.providerIds.contains(_sourceFilter)) return false;
      if (_languageFilter != null &&
          !entry.listings.any((listing) => listing.language?.toLowerCase() == _languageFilter)) {
        return false;
      }
      return true;
    }).toList();
    final query = WorkIdentityMatcher.normalizeTitle(_lastSubmittedQuery);
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
    if (_creatorMode) {
      await _searchCreators();
      return;
    }
    final query = _controller.text.trim();
    if (query.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    final nextHistory = <String>[
      query,
      ..._recentQueries.where((saved) => saved.toLowerCase() != query.toLowerCase()),
    ].take(6).toList(growable: false);
    _lastSubmittedQuery = query;
    setState(() {
      _recentQueries = List.unmodifiable(nextHistory);
      _loading = true;
      _error = null;
      _outcome = null;
    });
    try {
      // History persistence is best-effort; a settings write failure must not
      // turn a valid network search into a failed search.
      await widget.runtime.database?.setSetting('browser.recent_queries', nextHistory);
    } on Object {
      // Continue to the live search even if local history could not be saved.
    }
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

  Future<void> _switchBrowserMode(bool creators) async {
    if (_loading || creators == _creatorMode) return;
    setState(() {
      _creatorMode = creators;
      _creatorSearchPerformed = false;
      _lastCreatorQuery = '';
      _creatorResults = const [];
      _outcome = null;
      _error = null;
      _lastSubmittedQuery = '';
      _formatFilter = null;
      _sourceFilter = null;
      _languageFilter = null;
    });
    // Creator lookup is local-only, so it can be run immediately for an existing query.
    if (creators && _controller.text.trim().isNotEmpty) await _searchCreators();
  }

  Future<void> _searchCreators() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _creatorSearchPerformed = true;
      _lastCreatorQuery = query;
      _creatorResults = const [];
      _outcome = null;
    });
    try {
      final database = widget.runtime.database;
      if (database == null) throw StateError('Local creator catalog unavailable.');
      // Creator discovery queries only the bounded local index; it never calls a network provider.
      final creators = await database.searchCreatorProfiles(query, limit: 50);
      if (!mounted) return;
      setState(() => _creatorResults = creators);
    } on Object {
      if (!mounted) return;
      setState(() => _error = 'Local creator lookup could not complete. Check local storage and retry.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreator(CreatorProfile creator) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _CreatorDetailPage(runtime: widget.runtime, creator: creator),
      ),
    );
  }

  WorkCandidate _candidateForEntry(CatalogEntry entry) => _candidateForCatalogEntry(entry, widget.runtime);

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
          const Text('Search current provider results or explore creators already indexed on this device.',
              style: TextStyle(color: Colors.white60, height: 1.4)),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(value: false, label: Text('Stories'), icon: Icon(Icons.menu_book_rounded)),
              ButtonSegment<bool>(value: true, label: Text('Creators'), icon: Icon(Icons.person_search_rounded)),
            ],
            selected: {_creatorMode},
            showSelectedIcon: false,
            onSelectionChanged: _loading ? null : (selection) => _switchBrowserMode(selection.single),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: _creatorMode ? 'Creator name or pen name…' : 'Title, alternate title…',
                    prefixIcon: Icon(_creatorMode ? Icons.person_search_rounded : Icons.search_rounded),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() {
                              _controller.clear();
                              _outcome = null;
                              _error = null;
                              _lastSubmittedQuery = '';
                              _formatFilter = null;
                              _sourceFilter = null;
                              _languageFilter = null;
                              _creatorResults = const [];
                              _creatorSearchPerformed = false;
                              _lastCreatorQuery = '';
                            }),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _loading ? null : _search,
                icon: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.arrow_forward_rounded),
                tooltip: _creatorMode ? 'Find creators' : 'Search stories',
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (!_creatorMode && _outcome == null && !_loading && _error == null && _recentQueries.isNotEmpty) ...[
            Row(
              children: [
                const Expanded(child: _SectionHeading(title: 'Recent searches', subtitle: 'Stored privately on this device')),
                TextButton(
                  onPressed: () async {
                    setState(() => _recentQueries = const []);
                    try {
                      await widget.runtime.database?.setSetting('browser.recent_queries', const <String>[]);
                    } on Object {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Recent searches were cleared for this session but could not be saved.')),
                        );
                      }
                    }
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _recentQueries.map((query) => ActionChip(
                avatar: const Icon(Icons.history_rounded, size: 16),
                label: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
                onPressed: () {
                  _controller.text = query;
                  _search();
                },
              )).toList(growable: false),
            ),
            const SizedBox(height: 12),
          ],
          if (_outcome != null && _controller.text.trim() != _lastSubmittedQuery)
            _InlineNotice(
              icon: Icons.info_outline_rounded,
              text: 'Showing results for “$_lastSubmittedQuery”. Submit the new title to run another search.',
            ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) ...[
            _InlineNotice(icon: _creatorMode ? Icons.manage_search_rounded : Icons.wifi_off_rounded, text: _error!),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _loading || _controller.text.trim().isEmpty ? null : _search,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_creatorMode ? 'Search creators again' : 'Try search again'),
              ),
            ),
          ],
          if (_creatorMode && _creatorResults.isNotEmpty && _controller.text.trim() != _lastCreatorQuery)
            _InlineNotice(
              icon: Icons.info_outline_rounded,
              text: 'Showing creators for “$_lastCreatorQuery”. Submit the new name to search again.',
            ),
          if (_creatorMode && !_creatorSearchPerformed && !_loading && _error == null)
            const _InlineNotice(
              icon: Icons.person_search_rounded,
              text: 'Creator search uses the catalog already indexed on this device. Search Stories first to populate the local catalog; creator lookup itself does not contact a network source.',
            ),
          if (_creatorMode && _creatorSearchPerformed && !_loading && _error == null) ...[
            _SectionHeading(
              title: '${_creatorResults.length} creator${_creatorResults.length == 1 ? '' : 's'} found',
              subtitle: 'From locally indexed source metadata · no extra network request',
            ),
            const SizedBox(height: 12),
            if (_creatorResults.isEmpty)
              const _InlineNotice(
                icon: Icons.person_search_rounded,
                text: 'No indexed creators match this name. Try a shorter name, or search a title in Stories mode first.',
              )
            else
              for (final creator in _creatorResults) ...[
                _CreatorResultTile(creator: creator, onTap: () => _openCreator(creator)),
                const SizedBox(height: 10),
              ],
          ],
          if (_outcome != null) ...[
            _SectionHeading(
              title: '${_visibleEntries.length} of ${_outcome!.entries.length} unified results',
              subtitle: _outcome!.batch.hasPartialFailures
                  ? 'Some sources did not respond. Results are merged where identity matching is safe.'
                  : 'Across ${widget.runtime.providers.enabled.length} enabled sources · duplicate listings grouped safely.',
            ),
            const SizedBox(height: 12),
            if (_outcome!.entries.isNotEmpty) ...[
              if (_formatFilter != null || _sourceFilter != null || _languageFilter != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _formatFilter = null;
                      _sourceFilter = null;
                      _languageFilter = null;
                    }),
                    icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
                    label: const Text('Clear all filters'),
                  ),
                ),
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
          if (!_creatorMode && !_loading && _outcome == null && _error == null)
            const _InlineNotice(
              icon: Icons.public_rounded,
              text: 'Search uses live provider APIs. Results depend on source availability; Kurotoon does not host comic content.',
            ),
        ],
      );
}

WorkCandidate _candidateForCatalogEntry(CatalogEntry entry, KurotoonRuntime runtime) {
    if (entry.listings.isEmpty) throw StateError('Catalog entry has no source listings.');
    final candidates = entry.listings.toList();
    candidates.sort((left, right) {
      int priority(WorkCandidate candidate) {
        final providers = runtime.providers.all.where((item) => item.descriptor.id == candidate.providerId);
        if (providers.isEmpty) return 0;
        final provider = providers.first;
        final enabled = runtime.providers.isEnabled(candidate.providerId);
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

class _CreatorResultTile extends StatelessWidget {
  const _CreatorResultTile({required this.creator, required this.onTap});

  final CreatorProfile creator;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final aliases = creator.aliases.where((alias) => alias.trim().isNotEmpty).take(3).toList(growable: false);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _violet.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.person_outline_rounded, color: _violet),
        ),
        title: Text(creator.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          aliases.isEmpty ? 'Creator in your local catalog' : 'Also known as ' + aliases.join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
        onTap: onTap,
      ),
    );
  }
}

class _CreatorDetailPage extends StatefulWidget {
  const _CreatorDetailPage({required this.runtime, required this.creator});

  final KurotoonRuntime runtime;
  final CreatorProfile creator;

  @override
  State<_CreatorDetailPage> createState() => _CreatorDetailPageState();
}

class _CreatorDetailPageState extends State<_CreatorDetailPage> {
  CreatorProfile? _profile;
  List<CatalogEntry> _works = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final database = widget.runtime.database;
      if (database == null) throw StateError('Local catalog unavailable.');
      final profile = await database.loadCreatorProfile(widget.creator.id) ?? widget.creator;
      final works = await database.loadCreatorWorks(widget.creator.id, limit: 50);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _works = List.unmodifiable(works.where((entry) => entry.listings.isNotEmpty));
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() { _error = 'This local creator profile could not be loaded. Your saved library is unaffected.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final creator = _profile ?? widget.creator;
    final aliases = creator.aliases.where((alias) => alias.trim().isNotEmpty).take(8).toList(growable: false);
    return Scaffold(
      backgroundColor: _ink,
      appBar: AppBar(title: Text(creator.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xAA273C72), Color(0xAA17162F)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: .09)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 26,
                  backgroundColor: Color(0x3329D9F5),
                  child: Icon(Icons.person_rounded, color: _cyan, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(creator.name, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(
                      aliases.isEmpty ? 'Locally indexed creator profile' : 'Also known as ' + aliases.join(' · '),
                      style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Built from available catalog metadata. This is not a complete biography or an online creator lookup.',
                      style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.45),
                    ),
                  ],
                )),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeading(
            title: 'Works with this creator',
            subtitle: 'Up to 50 locally indexed works, sorted by title',
          ),
          const SizedBox(height: 12),
          if (_loading) const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ))
          else if (_error != null) Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InlineNotice(icon: Icons.storage_rounded, text: _error!),
              TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
            ],
          )
          else if (_works.isEmpty) const _InlineNotice(
            icon: Icons.menu_book_outlined,
            text: 'No readable catalog entries are linked to this creator yet. Try searching and saving another title.',
          )
          else ...[
            Text(_works.length.toString() + ' locally indexed works', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 10),
            for (final entry in _works) ...[
              Builder(builder: (context) {
                final candidate = _candidateForCatalogEntry(entry, widget.runtime);
                final sourceLabels = entry.providerIds.map((id) {
                  final providers = widget.runtime.providers.all.where((provider) => provider.descriptor.id == id);
                  return providers.isEmpty ? id : providers.first.descriptor.name;
                }).toList(growable: false);
                return _SearchResultTile(
                  candidate: candidate,
                  sourceLabels: sourceLabels,
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => SeriesDetailPage(runtime: widget.runtime, candidate: candidate),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
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
  const _MePage({
    required this.runtime,
    required this.motionEnabled,
    required this.motionSaving,
    required this.onMotionChanged,
  });
  final KurotoonRuntime runtime;
  final bool motionEnabled;
  final bool motionSaving;
  final ValueChanged<bool> onMotionChanged;

  @override
  State<_MePage> createState() => _MePageState();
}

class _MePageState extends State<_MePage> {
  bool _mangadexEnabled = true;
  bool _providerBusy = false;
  bool _rightToLeftDefault = false;
  bool _longStripDefault = false;
  bool _dataSaverDefault = false;
  bool _readerPreferenceSaving = false;
  ReaderDisplayPreferences _readerDisplayPreferences = const ReaderDisplayPreferences();

  @override
  void initState() {
    super.initState();
    _mangadexEnabled = widget.runtime.providers.isEnabled('mangadex');
    _restoreReaderDefaults();
  }

  Future<void> _restoreReaderDefaults() async {
    try {
      final database = widget.runtime.database;
      final rightToLeft = await database?.getSetting<bool>('reader.right_to_left');
      final longStrip = await database?.getSetting<bool>('reader.long_strip');
      final dataSaver = await database?.getSetting<bool>('reader.data_saver');
      final display = await database?.getSetting<Object?>('reader.display_preferences');
      if (!mounted) return;
      setState(() {
        _rightToLeftDefault = rightToLeft ?? false;
        _longStripDefault = longStrip ?? false;
        _dataSaverDefault = dataSaver ?? false;
        _readerDisplayPreferences = ReaderDisplayPreferences.fromStored(display);
      });
    } on Object {
      // Optional reader defaults should never prevent the rest of Me from opening.
    }
  }

  Future<void> _saveReaderPreference({
    required String key,
    required bool value,
    required bool previous,
    required ValueChanged<bool> update,
  }) async {
    if (_readerPreferenceSaving || value == previous) return;
    setState(() => _readerPreferenceSaving = true);
    try {
      final database = widget.runtime.database;
      if (database == null) throw StateError('Local settings are unavailable.');
      // Persist first, then update the switch: what the UI shows is always durable.
      await database.setSetting(key, value);
    } on Object {
      if (!mounted) return;
      setState(() => _readerPreferenceSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That reader preference could not be saved. Your previous setting was kept.')),
      );
      return;
    }
    if (!mounted) return;
    update(value);
    setState(() => _readerPreferenceSaving = false);
  }

  Future<void> _editReaderDisplayPreferences() async {
    if (_readerPreferenceSaving) return;
    final next = await showReaderDisplayPreferences(context, _readerDisplayPreferences);
    if (next == null || !mounted) return;
    setState(() => _readerPreferenceSaving = true);
    try {
      final database = widget.runtime.database;
      if (database == null) throw StateError('Local settings are unavailable.');
      await database.setSetting('reader.display_preferences', next.toMap());
    } on Object {
      if (!mounted) return;
      setState(() => _readerPreferenceSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reader display settings could not be saved. Your previous settings were kept.')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _readerDisplayPreferences = next;
      _readerPreferenceSaving = false;
    });
  }

  Future<void> _setMangaDexEnabled(bool value) async {
    if (_providerBusy) return;
    setState(() => _providerBusy = true);
    try {
      await widget.runtime.setProviderEnabled('mangadex', value);
      if (mounted) setState(() => _mangadexEnabled = value);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The source setting could not be saved. No change was applied.')),
        );
      }
    } finally {
      if (mounted) setState(() => _providerBusy = false);
    }
  }

  Widget _settingsCard(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.075)),
        ),
        child: Column(children: children),
      );

  Widget _settingsTile({
    required IconData icon,
    required Color tint,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
          child: Icon(icon, color: tint),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.35)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 136),
        children: [
          Row(
            children: [
              const _BrandMark(size: 48),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ME', style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w900, fontSize: 12, color: _violet)),
                    SizedBox(height: 4),
                    Text('Your reading, your rules.', style: TextStyle(fontSize: 23, height: 1.12, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xAA273C72), Color(0xAA17162F), Color(0x88101A2B)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_moon_outlined, color: _cyan, size: 25),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('A local-first reading space', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      SizedBox(height: 5),
                      Text(
                        'No account is required. Your library and reading progress live on this device; live searches contact the sources you enable.',
                        style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _SectionHeading(title: 'Reader defaults', subtitle: 'Applied when you open the next chapter'),
          const SizedBox(height: 10),
          _settingsCard([
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              secondary: const Icon(Icons.view_stream_rounded, color: _cyan),
              title: const Text('Long-strip / webtoon mode'),
              subtitle: const Text('Scroll vertically through tall pages'),
              value: _longStripDefault,
              onChanged: _readerPreferenceSaving ? null : (value) => _saveReaderPreference(
                key: 'reader.long_strip',
                value: value,
                previous: _longStripDefault,
                update: (next) => setState(() => _longStripDefault = next),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16, color: Colors.white12),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              secondary: const Icon(Icons.data_saver_on_rounded, color: Color(0xFFFFC58A)),
              title: const Text('Data saver by default'),
              subtitle: const Text('Prefer smaller source images when the provider supports them'),
              value: _dataSaverDefault,
              onChanged: _readerPreferenceSaving ? null : (value) => _saveReaderPreference(
                key: 'reader.data_saver',
                value: value,
                previous: _dataSaverDefault,
                update: (next) => setState(() => _dataSaverDefault = next),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16, color: Colors.white12),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              secondary: const Icon(Icons.swap_horiz_rounded, color: _violet),
              title: const Text('Read right to left'),
              subtitle: const Text('Use for right-to-left manga page order'),
              value: _rightToLeftDefault,
              onChanged: _readerPreferenceSaving ? null : (value) => _saveReaderPreference(
                key: 'reader.right_to_left',
                value: value,
                previous: _rightToLeftDefault,
                update: (next) => setState(() => _rightToLeftDefault = next),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16, color: Colors.white12),
            _settingsTile(
              icon: Icons.tune_rounded,
              tint: _violet,
              title: 'Display, dimming & spacing',
              subtitle: (_readerDisplayPreferences.fitMode == 'width'
                      ? 'Fit to width'
                      : _readerDisplayPreferences.fitMode == 'height'
                          ? 'Fit to height'
                          : 'Fit entire page') +
                  ' · Dimming ' + (_readerDisplayPreferences.dimming * 100).round().toString() +
                  '% · Gap ' + _readerDisplayPreferences.pageGap.round().toString() + ' px',
              onTap: _editReaderDisplayPreferences,
            ),
          ]),
          const SizedBox(height: 22),
          const _SectionHeading(title: 'Sources', subtitle: 'Choose which live providers can be queried'),
          const SizedBox(height: 10),
          _settingsCard([
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              secondary: const Icon(Icons.public_rounded, color: _cyan),
              title: const Text('MangaDex'),
              subtitle: Text(_providerBusy ? 'Updating source preference…' : 'Live API provider'),
              value: _mangadexEnabled,
              onChanged: _providerBusy ? null : _setMangaDexEnabled,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16, color: Colors.white12),
            _settingsTile(
              icon: Icons.health_and_safety_rounded,
              tint: _cyan,
              title: 'Source diagnostics',
              subtitle: 'Recent provider health and cooldown information',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => ProviderDiagnosticsPage(runtime: widget.runtime)),
              ),
            ),
          ]),
          const SizedBox(height: 22),
          const _SectionHeading(title: 'Extensions & repositories', subtitle: 'Review catalogs and manage supported source metadata'),
          const SizedBox(height: 10),
          _settingsCard([
            _settingsTile(
              icon: Icons.hub_rounded,
              tint: _violet,
              title: 'Manage repositories & extensions',
              subtitle: 'Preview, add, refresh, and remove compatible catalogs',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => RepositoryManagementPage(runtime: widget.runtime)),
              ),
            ),
          ]),
          const SizedBox(height: 22),
          const _SectionHeading(title: 'Storage & privacy', subtitle: 'Clean temporary files without deleting saved reading data'),
          const SizedBox(height: 10),
          _settingsCard([
            _settingsTile(
              icon: Icons.storage_rounded,
              tint: const Color(0xFFFFC58A),
              title: 'Storage & cache',
              subtitle: 'Review cached files and safely remove disposable items',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => StorageManagementPage(runtime: widget.runtime)),
              ),
            ),
          ]),
          const SizedBox(height: 22),
          const _SectionHeading(title: 'Galaxy', subtitle: 'Keep the atmosphere comfortable for your device'),
          const SizedBox(height: 10),
          _settingsCard([
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              secondary: const Icon(Icons.blur_on_rounded, color: _violet),
              title: const Text('Animated background'),
              subtitle: Text(widget.motionSaving
                  ? 'Saving motion preference…'
                  : 'Follows system reduced-motion settings and pauses in the background'),
              value: widget.motionEnabled,
              onChanged: widget.motionSaving ? null : widget.onMotionChanged,
            ),
          ]),
          const SizedBox(height: 22),
          const _InlineNotice(
            icon: Icons.info_outline_rounded,
            text: 'Kurotoon does not host comic content. Source availability and terms are controlled by each provider. Compiled extension APKs are not executed.',
          ),
        ],
      );
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
  int _quality = 2;
  int _slowFrameStreak = 0;
  int _fastFrameStreak = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_observeFrameTimings);
    if (widget.animated) _controller.repeat();
  }

  void _observeFrameTimings(List<FrameTiming> timings) {
    if (!mounted || !widget.animated) return;
    var quality = _quality;
    var slowFrames = _slowFrameStreak;
    var fastFrames = _fastFrameStreak;
    for (final timing in timings) {
      if (timing.totalSpan > const Duration(milliseconds: 20)) {
        slowFrames++;
        fastFrames = 0;
      } else if (timing.totalSpan < const Duration(milliseconds: 14)) {
        fastFrames++;
        slowFrames = 0;
      } else {
        slowFrames = 0;
        fastFrames = 0;
      }
      final nextQuality = nextGalaxyEffectQuality(
        currentQuality: quality,
        consecutiveSlowFrames: slowFrames,
        consecutiveFastFrames: fastFrames,
      );
      if (nextQuality != quality) {
        quality = nextQuality;
        slowFrames = 0;
        fastFrames = 0;
      }
    }
    _slowFrameStreak = slowFrames;
    _fastFrameStreak = fastFrames;
    if (quality != _quality) setState(() => _quality = quality);
  }

  @override
  void didUpdateWidget(covariant _GalaxyScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animated == widget.animated) return;
    _slowFrameStreak = 0;
    _fastFrameStreak = 0;
    if (widget.animated) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_observeFrameTimings);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => CustomPaint(
          painter: _GalaxyPainter(
            progress: widget.animated ? _controller.value : 0,
            quality: _quality,
          ),
          child: child,
        ),
        child: widget.child,
      );
}

class _GalaxyPainter extends CustomPainter {
  const _GalaxyPainter({required this.progress, this.quality = 2});
  final double progress;
  final int quality;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _ink);
    final blurSigma = quality == 0 ? 18.0 : quality == 1 ? 34.0 : 55.0;
    final glow = Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);
    final phase = progress * math.pi * 2;
    glow.color = const Color(0xFF30246F).withValues(alpha: 0.34);
    canvas.drawCircle(
      Offset(size.width * (0.16 + 0.09 * math.sin(phase)), size.height * 0.18),
      size.width * 0.34,
      glow,
    );
    if (quality >= 1) {
      glow.color = const Color(0xFF075B70).withValues(alpha: 0.24);
      canvas.drawCircle(
        Offset(size.width * (0.88 + 0.06 * math.cos(phase * 0.7)), size.height * 0.58),
        size.width * 0.32,
        glow,
      );
    }
    if (quality >= 2) {
      glow.color = const Color(0xFF34224F).withValues(alpha: 0.22);
      canvas.drawCircle(
        Offset(size.width * 0.48, size.height * (0.86 + 0.04 * math.sin(phase * 0.5))),
        size.width * 0.38,
        glow,
      );
    }

    final stars = Paint()..style = PaintingStyle.fill;
    final starCount = quality == 0 ? 24 : quality == 1 ? 60 : 100;
    for (var i = 0; i < starCount; i++) {
      final seed = i * 73.37 + 19.0;
      final x = ((math.sin(seed * 12.9898) * 43758.5453) % 1).abs() * size.width;
      final baseY = ((math.sin(seed * 78.233) * 12345.678) % 1).abs() * size.height;
      final y = (baseY + progress * (10 + (i % 17) * 2)) % size.height;
      final twinkle = 0.18 + 0.72 * ((math.sin(phase * (0.5 + (i % 5) * 0.1) + seed) + 1) / 2);
      stars.color = (i % 7 == 0 ? _cyan : Colors.white).withValues(alpha: twinkle);
      canvas.drawCircle(Offset(x, y), i % 11 == 0 ? 1.45 : 0.7 + (i % 3) * 0.22, stars);
    }
    if (quality > 0) {
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
  }

  @override
  bool shouldRepaint(covariant _GalaxyPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.quality != quality;
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
