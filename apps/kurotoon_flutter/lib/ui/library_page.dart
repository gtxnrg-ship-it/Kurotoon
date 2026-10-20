import 'package:flutter/material.dart';

import '../runtime.dart';
import '../storage/kurotoon_database.dart';

const _cyan = Color(0xFF6EE7F9);
const _violet = Color(0xFF9D8CFF);

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.runtime});
  final KurotoonRuntime runtime;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  LibraryStatus? _filter;
  bool _loading = true;
  String? _error;
  List<LibraryBook> _books = const [];

  @override
  void initState() { super.initState(); _reload(); }

  Future<void> _reload() async {
    setState(() { _loading = true; _error = null; });
    try {
      final service = widget.runtime.readingJourney;
      if (service == null) throw StateError('Persistent storage unavailable');
      final books = await service.loadLibrary(status: _filter);
      if (!mounted) return;
      setState(() { _books = books; _loading = false; });
    } on Object {
      if (!mounted) return;
      setState(() { _error = 'Your library could not be loaded. Your saved data has not been changed.'; _loading = false; });
    }
  }

  Future<void> _setStatus(LibraryBook book, LibraryStatus status) async {
    try {
      final service = widget.runtime.readingJourney;
      if (service == null) throw StateError('Persistent storage unavailable');
      await service.updateLibraryStatus(workId: book.record.workId, editionId: book.record.editionId, status: status);
      await _reload();
    } on Object {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update the reading status.')));
    }
  }

  Future<void> _remove(LibraryBook book) async {
    final title = book.catalogEntry?.work.title ?? 'this story';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from library?'),
        content: Text('Remove “$title” from your library?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final service = widget.runtime.readingJourney;
      if (service == null) throw StateError('Persistent storage unavailable');
      await service.removeFromLibrary(workId: book.record.workId, editionId: book.record.editionId);
      await _reload();
    } on Object {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not remove this item.')));
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _reload,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 130),
      children: [
        const Text('YOUR COLLECTION', style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w900, fontSize: 12, color: _cyan)),
        const SizedBox(height: 8),
        const Text('Your worlds, in one place.', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Saved on this device. Pull down to refresh.', style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 18),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          _chip('All', null),
          for (final status in LibraryStatus.values) ...[const SizedBox(width: 8), _chip(_label(status), status)],
        ])),
        const SizedBox(height: 18),
        if (_loading) const LinearProgressIndicator(minHeight: 2)
        else if (_error != null) _notice(Icons.storage_rounded, 'Library unavailable', _error!, TextButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Retry')))
        else if (_books.isEmpty) _notice(Icons.auto_stories_rounded, _filter == null ? 'Your collection starts here' : 'No ' + _label(_filter!).toLowerCase() + ' stories yet',
          _filter == null ? 'Browse a story and save it to your library. Your collection stays on this device.' : 'Choose another status or save a story from Browser.')
        else ...[
          Text(_books.length.toString() + (_books.length == 1 ? ' edition' : ' editions'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 10),
          for (final book in _books) ...[_bookCard(book), const SizedBox(height: 10)],
        ],
      ],
    ),
  );

  Widget _chip(String text, LibraryStatus? status) {
    final selected = _filter == status;
    return ChoiceChip(
      label: Text(text), selected: selected,
      onSelected: (_) { setState(() => _filter = status); _reload(); },
      selectedColor: _violet.withValues(alpha: .24),
      side: BorderSide(color: selected ? _violet.withValues(alpha: .7) : Colors.white12),
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.white70, fontSize: 12),
      backgroundColor: Colors.white.withValues(alpha: .04),
    );
  }

  Widget _bookCard(LibraryBook book) {
    final entry = book.catalogEntry;
    final title = entry?.work.title ?? 'Saved story';
    final cover = entry == null || entry.listings.isEmpty ? null : entry.listings.first.coverUrl;
    final progress = book.progress;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .055), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: .08))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 72, height: 100,
          child: cover == null ? const ColoredBox(color: Color(0xFF11182B), child: Icon(Icons.menu_book_rounded, color: Colors.white38))
          : Image.network(cover.toString(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF11182B), child: Icon(Icons.broken_image_outlined, color: Colors.white38))))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 6),
          Text([if (entry != null) _format(entry.work.format.name), if (book.edition?.languageCode != null) book.edition!.languageCode!.toUpperCase()].join(' · '), style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 8),
          Text(progress == null ? 'No reading progress saved' : 'Saved progress: ' + (progress.fraction * 100).round().toString() + '% through chapter', style: const TextStyle(color: _cyan, fontSize: 11)),
          const SizedBox(height: 8),
          DropdownButtonFormField<LibraryStatus>(
            value: book.record.status, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Reading status', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
            items: LibraryStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(_label(s), style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (s) { if (s != null && s != book.record.status) _setStatus(book, s); },
          ),
        ])),
        IconButton(tooltip: 'Remove from library', onPressed: () => _remove(book), icon: const Icon(Icons.delete_outline_rounded)),
      ]),
    );
  }

  Widget _notice(IconData icon, String title, String message, [Widget? action]) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .045), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: .08))),
    child: Column(children: [
      Icon(icon, size: 34, color: _violet), const SizedBox(height: 12),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 7), Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, height: 1.45)),
      if (action != null) ...[const SizedBox(height: 8), action],
    ]),
  );
}

String _label(LibraryStatus status) => switch (status) {
  LibraryStatus.reading => 'Reading',
  LibraryStatus.completed => 'Completed',
  LibraryStatus.planned => 'Plan to read',
  LibraryStatus.paused => 'Paused',
  LibraryStatus.dropped => 'Dropped',
  LibraryStatus.rereading => 'Re-reading',
};

String _format(String format) => switch (format) {
  'manga' => 'Manga', 'manhwa' => 'Manhwa', 'manhua' => 'Manhua',
  'webtoon' => 'Webtoon', 'oneShot' => 'One-shot', 'comic' => 'Comic',
  'novel' => 'Novel', _ => 'Story',
};
