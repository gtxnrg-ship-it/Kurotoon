import 'package:flutter/material.dart';
import 'package:kurotoon_core/kurotoon_core.dart';

import '../runtime.dart';

const _repoCyan = Color(0xFF6EE7F9);
const _repoViolet = Color(0xFF9D8CFF);
const _repoInk = Color(0xFF080B18);

class RepositoryManagementPage extends StatefulWidget {
  const RepositoryManagementPage({super.key, required this.runtime});
  final KurotoonRuntime runtime;

  @override
  State<RepositoryManagementPage> createState() => _RepositoryManagementPageState();
}

class _RepositoryManagementPageState extends State<RepositoryManagementPage> {
  final _urlController = TextEditingController();
  bool _loading = true;
  bool _working = false;
  String? _error;
  List<Map<String, Object?>> _repositories = const [];
  List<Map<String, Object?>> _installed = const [];
  final Map<String, ExtensionRepositoryIndex> _indexes = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final database = widget.runtime.database;
    if (database == null) {
      setState(() { _loading = false; _error = 'Persistent storage is unavailable.'; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        database.loadExtensionRepositories(),
        database.loadInstalledExtensions(),
      ]);
      if (!mounted) return;
      setState(() {
        _repositories = results[0];
        _installed = results[1];
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Repository settings could not be loaded. Your installed extensions were not changed.'; });
    }
  }

  Future<void> _addRepository() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || _working) return;
    setState(() { _working = true; _error = null; });
    try {
      final preview = await widget.runtime.previewExtensionRepository(url);
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(preview.index.name),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(preview.index.description ?? 'No description provided.'),
              const SizedBox(height: 12),
              Text('Repository ID: ${preview.index.id}'),
              Text('${preview.index.extensions.length} listed extensions'),
              const SizedBox(height: 12),
              const Text('KuroToon will re-fetch and verify this exact index digest before saving. Only declarative JSON extensions are supported; compiled APK extensions are not executed.'),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Review and add')),
          ],
        ),
      );
      if (accepted != true) return;
      await widget.runtime.addExtensionRepository(url, expectedPreviewDigest: preview.indexDigest);
      _urlController.clear();
      await _reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Repository added after identity and digest verification.')));
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Could not add repository: ${error is FormatException ? error.message : error.runtimeType}. Try a public GitHub repository, README.md, or direct HTTPS index.json URL.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openRepository(Map<String, Object?> repository) async {
    final id = repository['id'] as String?;
    if (id == null) return;
    setState(() { _working = true; _error = null; });
    try {
      final index = await widget.runtime.loadExtensionRepositoryIndex(id);
      if (!mounted) return;
      setState(() => _indexes[id] = index);
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Could not refresh this repository: ${error is FormatException ? error.message : error.runtimeType}.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _install(String repositoryId, String extensionId) async {
    setState(() { _working = true; _error = null; });
    try {
      await widget.runtime.installExtension(repositoryId: repositoryId, extensionId: extensionId);
      await _reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Declarative extension installed. Review its status before enabling it.')));
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Install failed safely: ${error is FormatException ? error.message : error.runtimeType}.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _toggleExtension(Map<String, Object?> extension, bool enabled) async {
    final id = extension['extension_id'] as String?;
    if (id == null) return;
    setState(() => _working = true);
    try {
      await widget.runtime.setExtensionEnabled(id, enabled);
      await _reload();
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Could not change extension state: ${error.runtimeType}. Check whether its manifest loaded correctly.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _uninstall(Map<String, Object?> extension) async {
    final id = extension['extension_id'] as String?;
    if (id == null) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uninstall extension?'),
        content: Text('Uninstall ${extension['name'] ?? id}? The local extension file will be removed only if its stored path passes the app-owned path safety checks. Your library and reading progress will be kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Uninstall')),
        ],
      ),
    );
    if (accepted != true) return;
    setState(() => _working = true);
    try {
      await widget.runtime.uninstallExtension(id);
      await _reload();
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Could not uninstall extension: ${error.runtimeType}.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _removeRepository(Map<String, Object?> repository) async {
    final id = repository['id'] as String?;
    if (id == null) return;
    if (repository['trust'] == RepositoryTrust.builtIn.name) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The built-in official repository cannot be removed.')));
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove repository?'),
        content: Text('Remove ${repository['name'] ?? id}? Installed extensions from this repository must be uninstalled first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await widget.runtime.database!.removeExtensionRepository(id);
      setState(() => _indexes.remove(id));
      await _reload();
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Repository was kept: ${error.runtimeType}. Uninstall its extensions first if any remain.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _repoInk,
    appBar: AppBar(
      title: const Text('Repositories & extensions'),
      backgroundColor: const Color(0xFF0B1020),
      actions: [IconButton(tooltip: 'Refresh repositories', onPressed: _loading || _working ? null : _reload, icon: const Icon(Icons.refresh_rounded))],
    ),
    body: RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        children: [
          const Text('SOURCE CONTROL', style: TextStyle(color: _repoCyan, letterSpacing: 2.5, fontSize: 11, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text('Choose what powers your worlds.', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text('Paste a public repository URL or README and KuroToon will look for a compatible JSON index. KuroToon installs declarative JSON manifests only; it does not execute third-party extension APKs.', style: TextStyle(color: Colors.white60, height: 1.45)),
          const SizedBox(height: 18),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addRepository(),
            decoration: const InputDecoration(labelText: 'Repository or index URL', hintText: 'https://github.com/owner/repository', prefixIcon: Icon(Icons.link_rounded)),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _working ? null : _addRepository,
            icon: _working ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_link_rounded),
            label: Text(_working ? 'Working…' : 'Preview repository'),
            style: FilledButton.styleFrom(backgroundColor: _repoViolet, foregroundColor: _repoInk),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _notice(_error!),
          ],
          const SizedBox(height: 24),
          const Text('INSTALLED REPOSITORIES', style: TextStyle(color: _repoCyan, letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (_loading) const LinearProgressIndicator(),
          if (!_loading && _repositories.isEmpty) _notice('No repositories have been saved yet.'),
          for (final repository in _repositories) _repositoryCard(repository),
          const SizedBox(height: 24),
          const Text('INSTALLED EXTENSIONS', style: TextStyle(color: _repoCyan, letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (_installed.isEmpty) _notice('No community extensions installed. The built-in MangaDex provider is managed separately.'),
          for (final extension in _installed) _extensionCard(extension),
        ],
      ),
    ),
  );

  Widget _repositoryCard(Map<String, Object?> repository) {
    final id = repository['id'] as String? ?? 'unknown';
    final index = _indexes[id];
    return Card(
      color: Colors.white.withValues(alpha: .045),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.hub_rounded, color: _repoViolet),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(repository['name'] as String? ?? id, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${repository['trust'] ?? 'userAdded'} · ${repository['index_url'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ])),
            IconButton(tooltip: 'Remove repository', onPressed: _working ? null : () => _removeRepository(repository), icon: const Icon(Icons.delete_outline_rounded)),
          ]),
          if (index != null) ...[
            const SizedBox(height: 8),
            Text(index.description ?? 'No description provided.', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            Text('${index.extensions.length} extensions available', style: const TextStyle(color: _repoCyan, fontSize: 12)),
            for (final extension in index.extensions) _packageRow(id, extension),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _working ? null : () => _openRepository(repository),
              icon: const Icon(Icons.sync_rounded),
              label: Text(index == null ? 'Refresh and browse' : 'Refresh index'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _packageRow(String repositoryId, ExtensionPackageEntry entry) {
    final installed = _installed.any((row) => row['extension_id'] == entry.id);
    final capabilities = entry.capabilities;
    final canSearch = capabilities.contains(ExtensionCapability.search);
    final canOpenSeries = capabilities.contains(ExtensionCapability.seriesDetails);
    final canListChapters = capabilities.contains(ExtensionCapability.chapterFeed);
    final canReadPages = capabilities.contains(ExtensionCapability.readerPages);
    final readerReady = canSearch && canOpenSeries && canListChapters && canReadPages;
    final capabilityLabel = readerReady
        ? 'Search + series + chapters + reader'
        : canReadPages && canListChapters
            ? 'Chapter reading · no search'
            : canSearch && !canListChapters
                ? 'Metadata/search only · cannot read chapters'
                : capabilities.map((capability) => capability.name).join(' · ');
    final capabilityColor = readerReady ? _repoCyan : const Color(0xFFFFC978);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 8),
      leading: Icon(
        readerReady ? Icons.auto_stories_rounded : Icons.info_outline_rounded,
        color: capabilityColor,
      ),
      title: Text(entry.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('v${entry.version}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 3),
            Text(capabilityLabel, style: TextStyle(color: capabilityColor, fontSize: 11, fontWeight: FontWeight.w600)),
            if (!readerReady)
              const Text(
                'Installing this source does not guarantee chapter pages or a working reader.',
                style: TextStyle(color: Colors.white54, fontSize: 10),
              ),
          ],
        ),
      ),
      trailing: TextButton(
        onPressed: _working || installed ? null : () => _install(repositoryId, entry.id),
        child: Text(installed ? 'Installed' : 'Install'),
      ),
    );
  }

  Widget _extensionCard(Map<String, Object?> extension) {
    final id = extension['extension_id'] as String? ?? '';
    final enabled = extension['enabled'] == 1 || extension['enabled'] == true;
    final loadError = widget.runtime.extensionLoadErrors[id];
    return Card(
      color: Colors.white.withValues(alpha: .045),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.extension_rounded, color: _repoViolet),
        title: Text(extension['name'] as String? ?? id, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          '${extension['version'] ?? 'unknown version'} · ${loadError ?? (enabled ? 'Enabled' : 'Disabled')}',
          style: TextStyle(color: loadError == null ? Colors.white54 : Colors.orangeAccent, fontSize: 11),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'enable') _toggleExtension(extension, true);
            if (action == 'disable') _toggleExtension(extension, false);
            if (action == 'uninstall') _uninstall(extension);
          },
          itemBuilder: (_) => [
            if (!enabled) const PopupMenuItem(value: 'enable', child: Text('Enable')),
            if (enabled) const PopupMenuItem(value: 'disable', child: Text('Disable')),
            const PopupMenuItem(value: 'uninstall', child: Text('Uninstall')),
          ],
        ),
      ),
    );
  }

  Widget _notice(String message) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .04), borderRadius: BorderRadius.circular(14)),
    child: Text(message, style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 12)),
  );
}
