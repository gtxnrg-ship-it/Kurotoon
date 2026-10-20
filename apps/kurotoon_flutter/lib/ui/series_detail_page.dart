import 'package:flutter/material.dart';
import 'package:kurotoon_core/kurotoon_core.dart';

import '../runtime.dart';
import '../services/reading_journey_service.dart';

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
      setState(() { _workId = entry.work.id; _warning = result.warning; _opening = false; });
      await _loadChapters(reset: true);
    } on Object {
      if (!mounted) return;
      setState(() { _error = 'Series details could not be loaded. Check the source connection and retry.'; _opening = false; });
    }
  }

  Future<void> _loadChapters({bool reset = false}) async {
    final workId = _workId;
    final service = _journey;
    if (workId == null || service == null || _loadingChapters) return;
    final offset = reset ? 0 : (_nextOffset ?? 0);
    if (!reset && _nextOffset == null) return;
    setState(() {
      _loadingChapters = true; _chapterError = null;
      if (reset) { _chapters = const []; _nextOffset = null; _editionId = null; }
    });
    try {
      final result = await service.refreshChapters(workId: workId, providerId: widget.candidate.providerId, offset: offset);
      if (!mounted) return;
      setState(() {
        _chapters = reset ? result.chapters : [..._chapters, ...result.chapters];
        _nextOffset = result.nextOffset;
        _editionId ??= result.editionIds.isEmpty ? null : result.editionIds.first;
        final notes = [if (_warning != null && _warning!.isNotEmpty) _warning!, if (result.warning != null) result.warning!];
        _warning = notes.isEmpty ? null : notes.join(' ');
        _loadingChapters = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() { _chapterError = 'Chapters could not be loaded. Your saved library and progress are unchanged.'; _loadingChapters = false; });
    }
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
          Text(_chapters.isEmpty && _loadingChapters ? 'Finding available chapters…' : _chapters.length.toString() + ' chapters loaded', style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 10),
          if (_chapters.isEmpty && !_loadingChapters && _chapterError == null)
            _notice(Icons.menu_book_rounded, 'No chapters loaded yet', 'Try refreshing the chapter list. Some sources may not provide chapter feeds.'),
          if (_chapterError != null) ...[
            _notice(Icons.wifi_off_rounded, 'Chapter feed unavailable', _chapterError!),
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _loadChapters(reset: _chapters.isEmpty), icon: const Icon(Icons.refresh), label: const Text('Retry chapters'))),
          ],
          for (var i = 0; i < _chapters.length; i++) ...[_chapterTile(_chapters[i], i), const SizedBox(height: 8)],
          if (_loadingChapters) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
          if (!_loadingChapters && _nextOffset != null) OutlinedButton.icon(onPressed: () => _loadChapters(), icon: const Icon(Icons.expand_more_rounded), label: const Text('Load more chapters')),
          if (!_loadingChapters && _chapters.isNotEmpty) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _loadChapters(reset: true), icon: const Icon(Icons.refresh), label: const Text('Refresh chapters'))),
        ],
      ]),
    );
  }

  Widget _chapterTile(ChapterUnit chapter, int index) {
    final number = chapter.chapterNumber;
    final label = chapter.title ?? (number == null ? 'Special chapter' : 'Chapter ' + (number == number.roundToDouble() ? number.toInt().toString() : number.toString()));
    final language = chapter.listings.map((item) => item.languageCode).whereType<String>().toSet().join(', ');
    return Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .045), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: .06))),
      child: ListTile(
        leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: _violet.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.menu_book_rounded, color: _violet, size: 19)),
        title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        subtitle: Text([if (chapter.volumeNumber != null) 'Vol. ' + chapter.volumeNumber.toString(), if (language.isNotEmpty) language, 'Chapter ' + (index + 1).toString() + ' in loaded list'].join(' · '), style: const TextStyle(color: Colors.white54, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The reader is the next integration step; this chapter is now available in the catalog.'))),
      ),
    );
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
