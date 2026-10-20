import 'package:flutter/material.dart';
import 'package:kurotoon_core/kurotoon_core.dart';

import '../runtime.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.runtime, required this.workId, required this.chapter});
  final KurotoonRuntime runtime;
  final String workId;
  final ChapterUnit chapter;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  ReaderPageManifest? _manifest;
  PageController? _controller;
  bool _loading = true;
  bool _dataSaver = false;
  String? _error;
  int _page = 0;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _controller?.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final service = widget.runtime.readingJourney;
      if (service == null) throw StateError('Reading service unavailable');
      final manifest = await service.loadReaderPages(widget.chapter, dataSaver: _dataSaver);
      final urls = manifest.urls(dataSaver: _dataSaver);
      final resume = await service.loadResumeTarget(workId: widget.workId, editionId: widget.chapter.editionId);
      var page = resume != null && resume.chapter?.id == widget.chapter.id
          ? (resume.progress.fraction * urls.length).ceil() - 1 : 0;
      if (page < 0) page = 0;
      if (page >= urls.length) page = urls.length - 1;
      if (!mounted) return;
      _controller?.dispose();
      _controller = PageController(initialPage: page);
      setState(() { _manifest = manifest; _page = page; _loading = false; });
      await _save(page, urls.length);
    } on Object {
      if (mounted) setState(() { _error = 'Could not load chapter pages. Check the connection and retry.'; _loading = false; });
    }
  }

  Future<void> _save(int page, int count) async {
    final service = widget.runtime.readingJourney;
    if (service == null || count < 1) return;
    try {
      await service.saveReadingProgress(
        workId: widget.workId,
        editionId: widget.chapter.editionId,
        chapterId: widget.chapter.id,
        fraction: ((page + 1) / count).clamp(0.0, 1.0).toDouble(),
        anchor: 'page:' + (page + 1).toString(),
      );
    } on Object {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reading progress could not be saved.')));
    }
  }

  Future<void> _adjacent(int direction) async {
    final service = widget.runtime.readingJourney;
    if (service == null) return;
    try {
      final next = await service.adjacentChapter(editionId: widget.chapter.editionId, currentChapterId: widget.chapter.id, direction: direction);
      if (next == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No adjacent chapter is loaded.')));
        return;
      }
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => ReaderPage(runtime: widget.runtime, workId: widget.workId, chapter: next),
      ));
    } on Object {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the adjacent chapter.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final urls = _manifest?.urls(dataSaver: _dataSaver) ?? const <Uri>[];
    final n = widget.chapter.chapterNumber;
    final title = widget.chapter.title ?? (n == null ? 'Special chapter' : 'Chapter ' + n.toString());
    return Scaffold(
      backgroundColor: const Color(0xFF080B18),
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [IconButton(
          tooltip: 'Toggle data saver',
          onPressed: _loading ? null : () { setState(() => _dataSaver = !_dataSaver); _load(); },
          icon: Icon(_dataSaver ? Icons.data_saver_on_rounded : Icons.data_saver_off_rounded),
        )],
      ),
      body: Column(children: [
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.wifi_off_rounded, size: 42), const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12), FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
              ])))
            : PageView.builder(
                controller: _controller, itemCount: urls.length,
                onPageChanged: (page) { setState(() => _page = page); _save(page, urls.length); },
                itemBuilder: (context, index) => InteractiveViewer(
                  minScale: 1, maxScale: 3,
                  child: Center(child: Image.network(urls[index].toString(), fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) => progress == null ? child : const CircularProgressIndicator(),
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 48))),
                ),
              )),
        Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          IconButton.filledTonal(onPressed: () => _adjacent(-1), icon: const Icon(Icons.skip_previous_rounded)),
          Expanded(child: Column(children: [
            if (urls.isNotEmpty) LinearProgressIndicator(value: (_page + 1) / urls.length),
            const SizedBox(height: 5),
            Text(urls.isEmpty ? 'Progress saved locally' : 'Page ' + (_page + 1).toString() + ' of ' + urls.length.toString(), style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ])),
          IconButton.filledTonal(onPressed: () => _adjacent(1), icon: const Icon(Icons.skip_next_rounded)),
        ])),
      ]),
    );
  }
}
