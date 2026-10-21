import 'package:flutter/material.dart';

import '../runtime.dart';
import '../services/reading_journey_service.dart';
import '../storage/kurotoon_database.dart';
import 'reader_page.dart';

const _cyan = Color(0xFF6EE7F9);
const _violet = Color(0xFF9D8CFF);

enum _LibrarySort { manualOrder, recentActivity, recentlyAdded, titleAscending, titleDescending }

String _librarySortLabel(_LibrarySort sort) => switch (sort) {
  _LibrarySort.manualOrder => 'Manual order',
  _LibrarySort.recentActivity => 'Recent activity',
  _LibrarySort.recentlyAdded => 'Recently added',
  _LibrarySort.titleAscending => 'Title (A–Z)',
  _LibrarySort.titleDescending => 'Title (Z–A)',
};

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.runtime});
  final KurotoonRuntime runtime;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  LibraryStatus? _filter;
  _LibrarySort _sort = _LibrarySort.recentActivity;
  bool _loading = true;
  bool _savingManualOrder = false;
  String? _error;
  List<LibraryBook> _books = const [];
  List<LibraryCollection> _collections = const [];
  String? _collectionFilter;
  Set<String> _collectionEditionIds = const {};
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final stored = await widget.runtime.database?.getSetting<String>('library.sort_mode');
      final matches = _LibrarySort.values.where((sort) => sort.name == stored).toList();
      if (mounted && matches.isNotEmpty) setState(() => _sort = matches.single);
    } on Object {
      // A missing preference should not prevent access to the saved library.
    }
    await _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<LibraryBook> get _visibleBooks {
    final query = _query.trim().toLowerCase();
    // Collection filtering and metadata search compose; both are local-only.
    return List.unmodifiable(_books.where((book) {
      if (_collectionFilter != null && !_collectionEditionIds.contains(book.record.editionId)) return false;
      if (query.isEmpty) return true;
      final work = book.catalogEntry?.work;
      final fields = <String>[
        work?.title ?? 'Saved story',
        if (work != null) ...work.alternateTitles,
        if (work != null) ...work.creatorNames,
        book.edition?.languageCode ?? '',
        book.edition?.title ?? '',
      ];
      return fields.any((field) => field.toLowerCase().contains(query));
    }));
  }

  DateTime _activityTime(LibraryBook book) =>
      book.progress?.updatedAt ?? book.record.lastOpenedAt ?? book.record.addedAt;

  bool get _canReorderLibrary =>
      _sort == _LibrarySort.manualOrder &&
      _filter == null &&
      _collectionFilter == null &&
      _query.trim().isEmpty &&
      _visibleBooks.length == _books.length;

  List<LibraryBook> _sortBooks(List<LibraryBook> books) {
    final sorted = List<LibraryBook>.of(books);
    switch (_sort) {
      case _LibrarySort.manualOrder:
        sorted.sort((a, b) {
          final order = a.record.sortOrder.compareTo(b.record.sortOrder);
          return order != 0 ? order : b.record.addedAt.compareTo(a.record.addedAt);
        });
        break;
      case _LibrarySort.recentActivity:
        sorted.sort((a, b) => _activityTime(b).compareTo(_activityTime(a)));
        break;
      case _LibrarySort.recentlyAdded:
        sorted.sort((a, b) => b.record.addedAt.compareTo(a.record.addedAt));
        break;
      case _LibrarySort.titleAscending:
        sorted.sort((a, b) => (a.catalogEntry?.work.title ?? 'Saved story')
            .toLowerCase()
            .compareTo((b.catalogEntry?.work.title ?? 'Saved story').toLowerCase()));
        break;
      case _LibrarySort.titleDescending:
        sorted.sort((a, b) => (b.catalogEntry?.work.title ?? 'Saved story')
            .toLowerCase()
            .compareTo((a.catalogEntry?.work.title ?? 'Saved story').toLowerCase()));
        break;
    }
    return sorted;
  }

  Future<void> _reorderBooks(int oldIndex, int newIndex) async {
    if (!_canReorderLibrary || _loading || _savingManualOrder) return;
    final ordered = List<LibraryBook>.of(_visibleBooks);
    if (oldIndex < 0 || oldIndex >= ordered.length) return;
    if (newIndex < 0 || newIndex >= ordered.length || newIndex == oldIndex) return;
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);
    setState(() {
      _savingManualOrder = true;
      _books = ordered;
    });
    try {
      final database = widget.runtime.database;
      if (database == null) throw StateError('Library storage is unavailable.');
      // The database validates the complete identity set again inside its transaction;
      // a stale screen can never overwrite a different or filtered library order.
      await database.reorderLibraryEntries(
        ordered.map((book) => book.record).toList(growable: false),
      );
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manual library order saved on this device.')),
        );
      }
    } on Object {
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manual order could not be saved. The stored order was restored. Refresh and try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingManualOrder = false);
    }
  }

  Future<void> _changeSort(_LibrarySort? next) async {
    if (next == null || next == _sort) return;
    setState(() {
      _sort = next;
      _books = _sortBooks(_books);
    });
    try {
      await widget.runtime.database?.setSetting('library.sort_mode', next.name);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sort preference changed for this session, but could not be saved.')),
        );
      }
    }
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final service = widget.runtime.readingJourney;
      final database = widget.runtime.database;
      if (service == null || database == null) throw StateError('Persistent storage unavailable');
      final results = await Future.wait<Object>([
        service.loadLibrary(status: _filter),
        database.loadLibraryCollections(),
      ]);
      final books = results[0] as List<LibraryBook>;
      final collections = results[1] as List<LibraryCollection>;
      final activeCollectionId = collections.any((item) => item.id == _collectionFilter) ? _collectionFilter : null;
      final members = activeCollectionId == null ? <String>{} : await database.loadLibraryCollectionEditionIds(activeCollectionId);
      if (!mounted) return;
      setState(() {
        _books = _sortBooks(books);
        _collections = collections;
        _collectionFilter = activeCollectionId;
        _collectionEditionIds = members;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() { _error = 'Your library or collections could not be loaded. Your saved data has not been changed.'; _loading = false; });
    }
  }

  Future<void> _selectCollection(String? collectionId) async {
    final database = widget.runtime.database;
    if (collectionId == null || database == null) {
      setState(() { _collectionFilter = null; _collectionEditionIds = const {}; });
      return;
    }
    try {
      final members = await database.loadLibraryCollectionEditionIds(collectionId);
      if (!mounted) return;
      setState(() { _collectionFilter = collectionId; _collectionEditionIds = members; });
    } on Object {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this collection. Your saved library remains unchanged.')),
      );
    }
  }

  Future<void> _createCollection() async {
    final controller = TextEditingController();
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Create a collection'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
            decoration: const InputDecoration(
              labelText: 'Collection name',
              hintText: 'Favorites, Weekend reads…',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: const Text('Create')),
          ],
        ),
      );
      final normalizedName = (name ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
      if (normalizedName.isEmpty) return;
      final id = 'collection-' + DateTime.now().toUtc().microsecondsSinceEpoch.toString();
      final database = widget.runtime.database;
      if (database == null) throw StateError('Local database unavailable');
      await database.createLibraryCollection(id: id, name: normalizedName);
      if (!mounted) return;
      setState(() => _collectionFilter = id);
      await _reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“' + normalizedName + '” is ready. Add saved stories with the folder menu on each card.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = error.toString().contains('UNIQUE constraint failed')
          ? 'A collection with that name already exists. Choose a different name.'
          : 'The collection could not be created. Your existing library was not changed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deleteCollection(LibraryCollection collection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "' + collection.name + '"?'),
        content: const Text('Only this collection and its organization are removed. The saved stories and reading progress stay in your library.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Keep collection')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete collection')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final database = widget.runtime.database;
      if (database == null) throw StateError('Local database unavailable');
      await database.removeLibraryCollection(collection.id);
      if (!mounted) return;
      if (_collectionFilter == collection.id) {
        setState(() { _collectionFilter = null; _collectionEditionIds = const {}; });
      }
      await _reload();
    } on Object {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete this collection. Your saved stories were kept.')),
      );
    }
  }

  Future<void> _addToCollection(LibraryBook book, LibraryCollection collection) async {
    try {
      final database = widget.runtime.database;
      if (database == null) throw StateError('Local database unavailable');
      final added = await database.addLibraryEntryToCollection(
        collectionId: collection.id,
        workId: book.record.workId,
        editionId: book.record.editionId,
      );
      if (!mounted) return;
      await _reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(added ? 'Added to "' + collection.name + '".' : 'Already in "' + collection.name + '".'),
      ));
    } on Object {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not organize this story. Your library and reading progress were kept.')),
      );
    }
  }

  Future<void> _removeFromCollection(LibraryBook book, LibraryCollection collection) async {
    try {
      final database = widget.runtime.database;
      if (database == null) throw StateError('Local database unavailable');
      final removed = await database.removeLibraryEntryFromCollection(
        collectionId: collection.id,
        workId: book.record.workId,
        editionId: book.record.editionId,
      );
      if (!mounted) return;
      await _reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(removed ? 'Removed from "' + collection.name + '". The story stays in your library.' : 'This story was no longer in that collection.'),
      ));
    } on Object {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update this collection. Your saved story was kept.')),
      );
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

  Future<void> _resume(LibraryBook book) async {
    final edition = book.edition;
    final service = widget.runtime.readingJourney;
    if (edition == null || service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This edition is not available for resume yet.')),
      );
      return;
    }
    try {
      final target = await service.loadResumeTarget(
        workId: book.record.workId,
        editionId: edition.id,
      );
      if (!mounted) return;
      if (target == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No saved reading position yet. Open a chapter first.')),
        );
        return;
      }
      if (!target.canResume || target.chapter == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(target.staleReason ?? 'Refresh this source before resuming.')),
        );
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ReaderPage(
            runtime: widget.runtime,
            workId: book.record.workId,
            chapter: target.chapter!,
          ),
        ),
      );
      if (mounted) await _reload();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not restore this reading position. Refresh the source and try again.')),
        );
      }
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
        Row(
          children: [
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Collections', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                SizedBox(height: 3),
                Text('Create your own shelves for saved editions', style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            )),
            IconButton.filledTonal(
              tooltip: 'Create collection',
              onPressed: _loading ? null : _createCollection,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            InputChip(
              label: const Text('All saved stories'),
              selected: _collectionFilter == null,
              onSelected: (_) => _selectCollection(null),
              selectedColor: _violet.withValues(alpha: .22),
            ),
            for (final collection in _collections) ...[
              const SizedBox(width: 8),
              InputChip(
                avatar: const Icon(Icons.folder_special_outlined, size: 17),
                label: Text('${collection.name} · ${collection.itemCount}', overflow: TextOverflow.ellipsis),
                selected: _collectionFilter == collection.id,
                onSelected: (_) => _selectCollection(_collectionFilter == collection.id ? null : collection.id),
                onDeleted: () => _deleteCollection(collection),
                selectedColor: _violet.withValues(alpha: .22),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'Search saved titles, creators, or editions',
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear library search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() {
                      _searchController.clear();
                      _query = '';
                    }),
                  ),
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<_LibrarySort>(
          initialValue: _sort,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Sort collection',
            isDense: true,
            prefixIcon: Icon(Icons.sort_rounded),
          ),
          items: _LibrarySort.values.map((sort) => DropdownMenuItem(
            value: sort,
            child: Text(_librarySortLabel(sort)),
          )).toList(),
          onChanged: _changeSort,
        ),
        const SizedBox(height: 18),
        if (_loading) const LinearProgressIndicator(minHeight: 2)
        else if (_error != null) _notice(Icons.storage_rounded, 'Library unavailable', _error!, TextButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Retry')))
        else if (_books.isEmpty && _collectionFilter != null && _collectionEditionIds.isEmpty && _query.trim().isEmpty) _notice(
          Icons.folder_open_rounded,
          'This collection is empty',
          'Use the folder menu on a saved story to add it here. Deleting this collection will not delete your saved stories.',
        )
        else if (_books.isEmpty) _notice(Icons.auto_stories_rounded, _filter == null ? 'Your collection starts here' : 'No ' + _label(_filter!).toLowerCase() + ' stories yet',
          _filter == null ? 'Browse a story and save it to your library. Your collection stays on this device.' : 'Choose another status or save a story from Browser.')
        else if (_visibleBooks.isEmpty) _notice(
          _collectionFilter != null ? Icons.folder_open_rounded : Icons.search_off_rounded,
          _collectionFilter != null && _query.trim().isEmpty ? 'This collection is empty' : 'No saved stories match',
          _collectionFilter != null && _query.trim().isEmpty
              ? 'Use the folder menu on a saved story to add it here. Deleting this collection will not delete your saved stories.'
              : 'Try a shorter title, a creator name, or clear the search to see your full collection.',
          TextButton.icon(
            onPressed: () => setState(() { _searchController.clear(); _query = ''; }),
            icon: const Icon(Icons.close_rounded),
            label: const Text('Clear search'),
          ),
        )
        else ...[
          Text('${_visibleBooks.length} of ${_books.length} ${_books.length == 1 ? 'edition' : 'editions'} · stored locally', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 10),
          if (_sort == _LibrarySort.manualOrder && !_canReorderLibrary)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: _cyan.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _cyan.withValues(alpha: .18)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: _cyan, size: 18),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'To change the saved order, show every saved edition: clear the status filter, collection selection, and search. This prevents a filtered view from moving hidden stories.',
                      style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          if (_sort == _LibrarySort.manualOrder && _canReorderLibrary)
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: _reorderBooks,
              children: [
                for (var index = 0; index < _visibleBooks.length; index++)
                  Padding(
                    key: ValueKey(_visibleBooks[index].record.workId + '::' + _visibleBooks[index].record.editionId),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _bookCard(_visibleBooks[index])),
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.drag_indicator_rounded, color: _cyan),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            )
          else
            for (final book in _visibleBooks) ...[_bookCard(book), const SizedBox(height: 10)],
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
          if (progress != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => _resume(book),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Resume reading'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          DropdownButtonFormField<LibraryStatus>(
            initialValue: book.record.status, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Reading status', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
            items: LibraryStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(_label(s), style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (s) { if (s != null && s != book.record.status) _setStatus(book, s); },
          ),
        ])),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              tooltip: 'Organize collections',
              enabled: _collections.isNotEmpty,
              icon: const Icon(Icons.folder_special_outlined, color: _violet),
              onSelected: (value) {
                final removing = value.startsWith('remove:');
                final id = value.substring(value.indexOf(':') + 1);
                final matches = _collections.where((item) => item.id == id);
                if (matches.isEmpty) return;
                if (removing) {
                  _removeFromCollection(book, matches.first);
                } else {
                  _addToCollection(book, matches.first);
                }
              },
              itemBuilder: (context) => _collections.map((collection) {
                final isCurrent = _collectionFilter == collection.id &&
                    _collectionEditionIds.contains(book.record.editionId);
                return PopupMenuItem<String>(
                  value: (isCurrent ? 'remove:' : 'add:') + collection.id,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 230),
                    child: Row(children: [
                      Icon(isCurrent ? Icons.folder_delete_outlined : Icons.folder_outlined, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        (isCurrent ? 'Remove from ' : 'Add to ') + collection.name,
                        overflow: TextOverflow.ellipsis,
                      )),
                    ]),
                  ),
                );
              }).toList(growable: false),
            ),
            IconButton(tooltip: 'Remove from library', onPressed: () => _remove(book), icon: const Icon(Icons.delete_outline_rounded)),
          ],
        ),
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
