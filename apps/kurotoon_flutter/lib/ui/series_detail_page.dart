import 'package:flutter/material.dart';
import 'package:kurotoon_core/kurotoon_core.dart';

import '../runtime.dart';
import '../services/reading_journey_service.dart';
import '../storage/kurotoon_database.dart';
import 'reader_page.dart';

const _cyan = Color(0xFF6EE7F9);
const _violet = Color(0xFF9D8CFF);
const _panel = Color(0xFF11182B);

class SeriesDetailPage extends StatefulWidget {
  const SeriesDetailPage({super.key, required this.runtime, required this.candidate});
  final KurotoonRuntime runtime;
  final WorkCandidate candidate;
  @override
  State<SeriesDetailPage> createState() => _SeriesDetailPageState();
}

class _SeriesDetailPageState extends State<SeriesDetailPage> {
  bool _opening = true;
  bool _loadingChapters = false;
  bool _saving = false;
  String? _error;
  String? _chapterError;
  String? _workId;
  String? _editionId;
  String? _warning;
  List<ChapterUnit> _chapters = const [];
  List<WorkCandidate> _sourceListings = const [];
  final Map<String, int?> _sourceOffsets = {};
  int? _nextOffset;
  bool _saved = false;
  ReadingJourneyService? get _journey => widget.runtime.readingJourney;

  @override
  void initState() { super.initState(); _open(); }

  Future<void> _open() async {
    setState(() { _opening = true; _error = null; });
    try {
      final service = _journey;
      if (service == null) throw StateError('Persistent storage is unavailable.');
      final result = await service.openSeries(widget.candidate);
      if (!mounted) return;
      final entry = result.catalogResult.entry;
      if (entry == null) {
        setState(() { _error = result.catalogResult.message ?? 'This source needs an identity review before the series can be opened.'; _opening = false; });
        return;
      }
      setState(() {
        _workId = entry.work.id;
        _sourceListings = entry.listings;
        _warning = result.warning;
        _opening = false;
      });
      await _loadChapters(reset: true);
    } on Object {
      if (!mounted) return;
      setState(() { _error = 'Series details could not be loaded. Check the source connection and retry.'; _opening = false; });
    }
  }

  List<String> _eligibleChapterProviders() {
    final ids = <String>{};
    for (final listing in _sourceListings) {
      final matches = widget.runtime.providers.all.where((item) => item.descriptor.id == listing.providerId);
      if (matches.isEmpty) continue;
      final provider = matches.first;
      if (!widget.runtime.providers.isEnabled(listing.providerId) ||
          !provider.descriptor.supports(ProviderCapability.chapters)) continue;
      ids.add(listing.providerId);
    }
    // A newly opened listing can be the first one saved to the catalog.
    if (ids.isEmpty) {
      final matches = widget.runtime.providers.all.where((item) => item.descriptor.id == widget.candidate.providerId);
      if (matches.isNotEmpty &&
          widget.runtime.providers.isEnabled(widget.candidate.providerId) &&
          matches.first.descriptor.supports(ProviderCapability.chapters)) {
        ids.add(widget.candidate.providerId);
      }
    }
    // Prefer the source the user opened, then keep the remaining source order stable.
    return [
      if (ids.remove(widget.candidate.providerId)) widget.candidate.providerId,
      ...ids,
    ];
  }

  Future<void> _loadChapters({bool reset = false}) async {
    final workId = _workId;
    final service = _journey;
    if (workId == null || service == null || _loadingChapters) return;
    if (!reset && _nextOffset == null) return;
    final sourceIds = _eligibleChapterProviders();
    setState(() {
      _loadingChapters = true;
      _chapterError = null;
      if (reset) {
        _chapters = const [];
        _sourceOffsets.clear();
        _nextOffset = null;
        _editionId = null;
      }
    });
    try {
      final fetched = <ChapterUnit>[];
      final nextOffsets = Map<String, int?>.from(_sourceOffsets);
      final warnings = <String>[];
      var attempted = 0;
      for (final providerId in sourceIds) {
        final offset = reset ? 0 : nextOffsets[providerId];
        if (!reset && offset == null) continue;
        attempted++;
        try {
          final result = await service.refreshChapters(
            workId: workId,
            providerId: providerId,
            offset: offset ?? 0,
          );
          fetched.addAll(result.chapters);
          nextOffsets[providerId] = result.nextOffset;
          if (result.warning != null && result.warning!.trim().isNotEmpty) {
            warnings.add('${providerId}: ${result.warning}');
          }
        } on Object catch (error) {
          nextOffsets[providerId] = null;
          warnings.add('${providerId}: chapter feed unavailable (${error.runtimeType})');
        }
      }
      final merged = _mergeChapterVariants(reset ? const <ChapterUnit>[] : _chapters, fetched);
      if (!mounted) return;
      setState(() {
        _chapters = merged;
        _sourceOffsets
          ..clear()
          ..addAll(nextOffsets);
        _nextOffset = nextOffsets.values.any((offset) => offset != null) ? 1 : null;
        _editionId ??= merged.isEmpty ? null : merged.first.editionId;
        final notes = [
          if (_warning != null && _warning!.isNotEmpty) _warning!,
          ...warnings,
        ];
        _warning = notes.isEmpty ? null : notes.toSet().join(' ');
        _loadingChapters = false;
        if (merged.isEmpty && warnings.isNotEmpty) {
          _chapterError = 'No compatible source returned chapters. ' + warnings.join(' · ');
        } else if (attempted == 0 && merged.isEmpty) {
          _chapterError = 'No enabled source currently supports chapter feeds.';
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _chapterError = 'Chapters could not be loaded. Your saved library and progress are unchanged.';
        _loadingChapters = false;
      });
    }
  }

  List<ChapterUnit> _mergeChapterVariants(
    Iterable<ChapterUnit> existing,
    Iterable<ChapterUnit> incoming,
  ) {
    // Keep the source-specific ChapterUnit intact. A synthetic chapter that
    // combines edition IDs would break resume and previous/next navigation.
    final unique = <String, ChapterUnit>{};
    for (final chapter in [...existing, ...incoming]) {
      final key = chapter.listings.isEmpty
          ? '${chapter.editionId}:${chapter.id}'
          : chapter.listings.map((listing) => listing.key).join('|');
      unique.putIfAbsent(key, () => chapter);
    }
    final result = unique.values.toList()
      ..sort((left, right) {
        final a = left.chapterNumber;
        final b = right.chapterNumber;
        if (a == null && b != null) return 1;
        if (a != null && b == null) return -1;
        if (a != null && b != null && a != b) return b.compareTo(a);
        final languageA = left.listings.isEmpty ? '' : (left.listings.first.languageCode ?? '');
        final languageB = right.listings.isEmpty ? '' : (right.listings.first.languageCode ?? '');
        final languageOrder = languageA.compareTo(languageB);
        if (languageOrder != 0) return languageOrder;
        final sourceA = left.listings.isEmpty ? '' : left.listings.first.providerId;
        final sourceB = right.listings.isEmpty ? '' : right.listings.first.providerId;
        return sourceA.compareTo(sourceB);
      });
    return List.unmodifiable(result);
  }

  Future<void> _addToLibrary() async {
    final workId = _workId;
    final service = _journey;
    if (workId == null || service == null || _saving) return;
    setState(() => _saving = true);
    try {
      await service.addToLibrary(workId: workId, providerId: widget.candidate.providerId, languageCode: 'en', status: LibraryStatus.planned);
      if (!mounted) return;
      setState(() { _saved = true; _saving = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to your library · Plan to read')));
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save this series. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final chapterGroups = const UnifiedChapterGrouping().group(_chapters);
    return Scaffold(
      backgroundColor: const Color(0xFF080B18),
      appBar: AppBar(title: const Text('Series details'), backgroundColor: const Color(0xFF0B1020)),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(width: 112, height: 158,
            child: candidate.coverUrl == null
              ? const ColoredBox(color: _panel, child: Icon(Icons.menu_book_rounded, size: 38, color: Colors.white38))
              : Image.network(candidate.coverUrl.toString(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: _panel, child: Icon(Icons.broken_image_outlined, color: Colors.white38))))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(candidate.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1.15)),
            const SizedBox(height: 9),
            Text(candidate.providerId.toUpperCase(), style: const TextStyle(letterSpacing: 1.4, color: _violet, fontSize: 11, fontWeight: FontWeight.w800)),
            if (candidate.creatorNames.isNotEmpty) ...[const SizedBox(height: 8), Text(candidate.creatorNames.join(', '), style: const TextStyle(color: Colors.white70, fontSize: 12))],
            if (candidate.year != null) ...[const SizedBox(height: 5), Text('Published ' + candidate.year.toString(), style: const TextStyle(color: Colors.white54, fontSize: 12))],
            if (candidate.tags.isNotEmpty) ...[const SizedBox(height: 8), Text(candidate.tags.take(6).join(' · '), style: const TextStyle(color: _cyan, fontSize: 11, height: 1.4))],
          ])),
        ]),
        const SizedBox(height: 18),
        if (_opening) const LinearProgressIndicator(minHeight: 2),
        if (_error != null) ...[
          _notice(Icons.info_outline_rounded, 'Details unavailable', _error!),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _open, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ],
        if (_warning != null && _warning!.trim().isNotEmpty) _notice(Icons.info_outline_rounded, 'Source note', _warning!),
        if (_workId != null) ...[
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _saving || _saved ? null : _addToLibrary,
            icon: Icon(_saved ? Icons.check_circle_rounded : Icons.bookmark_add_rounded),
            label: Text(_saving ? 'Saving…' : _saved ? 'Added to library' : 'Add to Library'),
            style: FilledButton.styleFrom(backgroundColor: _violet, foregroundColor: const Color(0xFF080B18), padding: const EdgeInsets.symmetric(vertical: 14))),
          const SizedBox(height: 26),
          const Text('CHAPTERS', style: TextStyle(letterSpacing: 2.5, color: _cyan, fontSize: 12, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(_chapters.isEmpty && _loadingChapters
              ? 'Finding available chapters…'
              : '${chapterGroups.length} unified chapters · ${_chapters.length} source releases',
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 10),
          if (_chapters.isEmpty && !_loadingChapters && _chapterError == null)
            _notice(Icons.menu_book_rounded, 'No chapters loaded yet', 'Try refreshing the chapter list. Some sources may not provide chapter feeds.'),
          if (_chapterError != null) ...[
            _notice(Icons.wifi_off_rounded, 'Chapter feed unavailable', _chapterError!),
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _loadChapters(reset: _chapters.isEmpty), icon: const Icon(Icons.refresh), label: const Text('Retry chapters'))),
          ],
          for (final group in chapterGroups) ...[_chapterTile(group), const SizedBox(height: 8)],
          if (_loadingChapters) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
          if (!_loadingChapters && _nextOffset != null) OutlinedButton.icon(onPressed: () => _loadChapters(), icon: const Icon(Icons.expand_more_rounded), label: const Text('Load more chapters')),
          if (!_loadingChapters && _chapters.isNotEmpty) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _loadChapters(reset: true), icon: const Icon(Icons.refresh), label: const Text('Refresh chapters'))),
        ],
      ]),
    );
  }

  Widget _chapterTile(UnifiedChapterGroup group) {
    final chapter = group.representative;
    final number = chapter.chapterNumber;
    final label = chapter.title ?? (number == null
        ? 'Special chapter'
        : 'Chapter ' + (number == number.roundToDouble() ? number.toInt().toString() : number.toString()));
    final language = chapter.listings.map((item) => item.languageCode).whereType<String>().toSet().join(', ');
    final sourceNames = group.providerIds.map((id) {
      final providers = widget.runtime.providers.all.where((provider) => provider.descriptor.id == id);
      return providers.isEmpty ? id : providers.first.descriptor.name;
    }).toList(growable: false);
    return Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .045), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: .06))),
      child: ListTile(
        leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: _violet.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.menu_book_rounded, color: _violet, size: 19)),
        title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        subtitle: Text([
          if (chapter.volumeNumber != null) 'Vol. ' + chapter.volumeNumber.toString(),
          if (language.isNotEmpty) language,
          if (sourceNames.length > 1) '${sourceNames.length} sources · choose on open'
          else if (sourceNames.isNotEmpty) sourceNames.first,
        ].join(' · '), style: const TextStyle(color: Colors.white54, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        onTap: () => _openUnifiedChapter(group),
      ),
    );
  }

  Future<void> _openUnifiedChapter(UnifiedChapterGroup group) async {
    final workId = _workId;
    if (workId == null) return;
    var chapter = group.representative;
    if (group.chapters.length > 1) {
      final chosen = await showDialog<ChapterUnit>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Choose a chapter source'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final variant in group.chapters)
                  ListTile(
                    leading: const Icon(Icons.public_rounded),
                    title: Text(_sourceNameForChapter(variant)),
                    subtitle: Text([
                      if (variant.listings.isNotEmpty && variant.listings.first.languageCode != null)
                        variant.listings.first.languageCode!,
                      if (variant.listings.isNotEmpty && variant.listings.first.releaseGroup != null)
                        variant.listings.first.releaseGroup!,
                    ].join(' · ')),
                    onTap: () => Navigator.of(context).pop(variant),
                  ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
        ),
      );
      if (chosen == null || !mounted) return;
      chapter = chosen;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReaderPage(runtime: widget.runtime, workId: workId, chapter: chapter),
      ),
    );
  }

  String _sourceNameForChapter(ChapterUnit chapter) {
    if (chapter.listings.isEmpty) return 'Unknown source';
    final id = chapter.listings.first.providerId;
    final providers = widget.runtime.providers.all.where((provider) => provider.descriptor.id == id);
    return providers.isEmpty ? id : providers.first.descriptor.name;
  }

  Widget _notice(IconData icon, String title, String message) => Container(
    margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .045), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: .07))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: _cyan, size: 20), const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4),
        Text(message, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
      ])),
    ]),
  );
}
