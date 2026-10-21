import 'package:flutter/material.dart';
import '../runtime.dart';
import '../storage/cache_storage_service.dart';
import '../storage/kurotoon_database.dart';

const _storageInk = Color(0xFF080B18);
const _storageCyan = Color(0xFF6EE7F9);
const _storageViolet = Color(0xFF9D8CFF);

class StorageManagementPage extends StatefulWidget {
  const StorageManagementPage({super.key, required this.runtime});
  final KurotoonRuntime runtime;

  @override
  State<StorageManagementPage> createState() => _StorageManagementPageState();
}

class _StorageManagementPageState extends State<StorageManagementPage> {
  bool _loading = true;
  bool _working = false;
  bool _recovering = false;
  bool _previewingBudget = false;
  int _incomingEstimateMiB = 25;
  CacheWritePlan? _budgetPreview;
  String? _budgetPreviewError;
  String? _error;
  String? _recoveryError;
  CacheRecoveryReport? _recoveryReport;
  List<CacheEntryFile> _entries = const [];
  final Set<String> _removing = {};

  int get _totalBytes => _entries.fold<int>(0, (total, item) => total + item.entry.bytes);
  int get _pinnedBytes => _entries.where((item) => item.entry.pinned).fold<int>(0, (total, item) => total + item.entry.bytes);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final database = widget.runtime.database;
    if (database == null) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Local storage is unavailable.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _recoveryError = null;
      _budgetPreview = null;
      _budgetPreviewError = null;
    });
    try {
      final entries = await database.loadCacheEntries();
      CacheRecoveryReport? report;
      String? recoveryError;
      try {
        // Startup recovery runs before the cache service is returned. Keep its
        // status separate so diagnostic failures cannot hide indexed cache data.
        report = (await widget.runtime.cacheStorage).lastRecoveryReport;
      } on Object catch (error) {
        recoveryError = 'Recovery status unavailable: ${error.runtimeType}.';
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _recoveryReport = report;
        _recoveryError = recoveryError;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Storage details could not be loaded: ${error.runtimeType}.';
      });
    }
  }

  Future<void> _recoverNow() async {
    if (_working || _loading || _recovering) return;
    final database = widget.runtime.database;
    if (database == null) {
      setState(() => _recoveryError = 'Local storage is unavailable.');
      return;
    }
    setState(() {
      _working = true;
      _recovering = true;
      _recoveryError = null;
    });
    try {
      final cache = await widget.runtime.cacheStorage;
      final report = await cache.recoverInterruptedOperations();
      final entries = await database.loadCacheEntries();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _budgetPreview = null;
        _budgetPreviewError = null;
        _recoveryReport = report;
        _recoveryError = report.complete
            ? null
            : 'Some cache files could not be reconciled safely. They were preserved for another recovery attempt.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            report.complete
                ? (report.changed
                    ? 'Cache recovery completed. ${report.operationsRecovered} interrupted operation(s) recovered.'
                    : 'Cache recovery checked; no repair was needed.')
                : 'Cache recovery is incomplete. Unresolved files were preserved.',
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _recoveryError = 'Cache recovery could not complete: ${error.runtimeType}.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _recovering = false;
        });
      }
    }
  }

  Future<void> _previewCacheBudget() async {
    if (_previewingBudget || _loading || _working) return;
    final database = widget.runtime.database;
    if (database == null) {
      setState(() => _budgetPreviewError = 'Local storage is unavailable.');
      return;
    }
    setState(() {
      _previewingBudget = true;
      _budgetPreviewError = null;
    });
    try {
      final plan = await database.planCacheWrite(
        incomingBytes: _incomingEstimateMiB * 1024 * 1024,
        budget: widget.runtime.storageBudget,
      );
      if (!mounted) return;
      setState(() => _budgetPreview = plan);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _budgetPreviewError = 'Budget preview failed: ${error.runtimeType}.');
    } finally {
      if (mounted) setState(() => _previewingBudget = false);
    }
  }

  Widget _budgetForecastCard() {
    final budgetBytes = widget.runtime.storageBudget.maxBytes;
    final usedRatio = (_totalBytes / budgetBytes).clamp(0.0, 1.0).toDouble();
    final usedPercent = (_totalBytes * 100 / budgetBytes).round();
    final plan = _budgetPreview?.storagePlan;
    final planColor = plan == null
        ? Colors.white70
        : plan.accepted
            ? _storageCyan
            : Colors.orangeAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.speed_rounded, color: _storageCyan),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Cache budget & forecast',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              Text('READ ONLY', style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '${_bytes(_totalBytes)} used',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '${_bytes(budgetBytes)} budget',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: usedRatio,
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                _totalBytes > budgetBytes ? Colors.orangeAccent : _storageCyan,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '\$usedPercent% of the cache budget used · ${_bytes((budgetBytes - _totalBytes).clamp(0, budgetBytes).toInt())} headroom',
            style: TextStyle(
              color: _totalBytes > budgetBytes ? Colors.orangeAccent : Colors.white54,
              fontSize: 11,
            ),
          ),
          const Divider(height: 22, color: Colors.white12),
          const Text(
            'Preview a hypothetical new cache item',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            'This is a dry run only. Kurotoon calculates which unpinned cache items would need eviction; nothing is downloaded or deleted.',
            style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _incomingEstimateMiB,
                  decoration: const InputDecoration(
                    labelText: 'Estimated incoming size',
                    suffixText: 'MiB',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [5, 25, 50, 100, 250]
                      .map((value) => DropdownMenuItem<int>(
                            value: value,
                            child: Text(value.toString() + ' MiB'),
                          ))
                      .toList(growable: false),
                  onChanged: _previewingBudget || _working
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _incomingEstimateMiB = value;
                            _budgetPreview = null;
                            _budgetPreviewError = null;
                          });
                        },
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: _loading || _working || _previewingBudget ? null : _previewCacheBudget,
                icon: _previewingBudget
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.calculate_outlined),
                label: const Text('Preview'),
              ),
            ],
          ),
          if (_budgetPreviewError != null) ...[
            const SizedBox(height: 10),
            Text(_budgetPreviewError!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ],
          if (plan != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(plan.accepted ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded, color: planColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    plan.accepted ? 'Estimated write fits the cache budget' : 'Estimated write cannot be safely accommodated',
                    style: TextStyle(color: planColor, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              plan.reason,
              style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
            ),
            if (plan.accepted && _budgetPreview!.filesToEvict.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${_budgetPreview!.filesToEvict.length} unpinned cache item(s) would be evicted; projected cache size ${_bytes(plan.projectedBytes)}.',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              )
            else if (plan.accepted)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'No eviction required; projected cache size ${_bytes(plan.projectedBytes)}.',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _remove(CacheEntryFile entry) async {
    if (_working || _removing.contains(entry.entry.key)) return;
    if (entry.entry.pinned) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pinned cache items are protected. Unpin them through their owning feature first.')));
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove cached item?'),
        content: Text('Remove ${entry.entry.key}? This only clears disposable cached bytes. Your library, chapter progress, and repository settings are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove cache')),
        ],
      ),
    );
    if (accepted != true) return;
    setState(() { _working = true; _removing.add(entry.entry.key); _error = null; });
    try {
      final cache = await widget.runtime.cacheStorage;
      await cache.remove(entry.entry.key);
      await _reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cached item removed. Saved reading data was not touched.')));
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Cache item was kept if safe removal could not complete: ${error.runtimeType}.');
    } finally {
      if (mounted) setState(() { _working = false; _removing.remove(entry.entry.key); });
    }
  }

  String _bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _storageInk,
    appBar: AppBar(
      title: const Text('Storage & Cache'),
      backgroundColor: const Color(0xFF0B1020),
      actions: [
        IconButton(tooltip: 'Refresh storage', onPressed: _loading || _working ? null : _reload, icon: const Icon(Icons.refresh_rounded)),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xCC273C72), Color(0xCC17162F), Color(0xAA101A2B)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: .12)),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.shield_outlined, color: _storageCyan, size: 30),
              SizedBox(height: 12),
              Text('Your data stays yours.', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
              SizedBox(height: 8),
              Text(
                'Manage disposable cache separately from your saved library, reading positions, and repository settings.',
                style: TextStyle(color: Colors.white70, height: 1.45),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          const Text('YOUR DEVICE STORAGE', style: TextStyle(color: _storageCyan, letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (_error != null) _notice(_error!, warning: true),
          if (_loading) const LinearProgressIndicator(),
          Row(children: [
            Expanded(child: _stat('Cache footprint', _bytes(_totalBytes), Icons.storage_rounded)),
            const SizedBox(width: 10),
            Expanded(child: _stat('Protected cache', _bytes(_pinnedBytes), Icons.lock_outline_rounded)),
          ]),
          const SizedBox(height: 12),
          _budgetForecastCard(),
          _notice('Cache entries: ${_entries.length}. Clearing cache removes only disposable files; the SQLite library and saved reading progress are separate.'),
          const SizedBox(height: 10),
          _recoveryCard(),
          const SizedBox(height: 20),
          const Text('CACHED CONTENT', style: TextStyle(color: _storageCyan, letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (!_loading && _entries.isEmpty) _notice('Your cache is empty. Content will appear here after features explicitly cache data.'),
          for (final item in _entries) _cacheTile(item),
        ],
      ),
    ),
  );

  Widget _recoveryCard() {
    final report = _recoveryReport;
    final color = _recoveryError != null
        ? Colors.orangeAccent
        : report != null && !report.complete
            ? Colors.orangeAccent
            : _storageCyan;
    final state = _recoveryError != null
        ? 'Needs attention'
        : report == null
            ? 'Not available'
            : !report.complete
                ? 'Partially recovered'
                : report.changed
                    ? 'Repairs completed'
                    : 'No repairs needed';
    String count(int value) => value.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_outlined, color: color),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Cache integrity & recovery',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              if (_recovering)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(state, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            _recoveryError ??
                (report == null
                    ? 'Recovery results are not available yet.'
                    : report.complete
                        ? 'Interrupted cache operations and abandoned cache files were checked on this device.'
                        : 'Some files could not be safely reconciled. They were kept for a later retry.'),
            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          if (report != null) ...[
            const SizedBox(height: 12),
            _recoveryMetric('Interrupted operations recovered', count(report.operationsRecovered)),
            _recoveryMetric('Abandoned temporary files removed', count(report.pendingFilesRemoved)),
            _recoveryMetric('Backup files reconciled', count(report.orphanBackupsHandled)),
            _recoveryMetric('Unindexed cache files removed', count(report.orphanFilesRemoved)),
            _recoveryMetric('Unresolved operations/errors', count(report.failures)),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _loading || _working ? null : _recoverNow,
              icon: const Icon(Icons.healing_rounded),
              label: Text(_recovering ? 'Checking cache…' : 'Check and repair cache'),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Repairs apply only to disposable cache files and cache metadata. Your saved stories and reading progress are kept separate.',
            style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _recoveryMetric(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );

  Widget _cacheTile(CacheEntryFile item) {
    final entry = item.entry;
    return Card(
      color: Colors.white.withValues(alpha: .045),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(entry.pinned ? Icons.push_pin_rounded : Icons.insert_drive_file_outlined, color: entry.pinned ? _storageViolet : _storageCyan),
        title: Text(entry.key, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        subtitle: Text('${entry.bucket.name} · ${_bytes(entry.bytes)} · ${entry.pinned ? 'Pinned' : 'Disposable'}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
        trailing: IconButton(
          tooltip: entry.pinned ? 'Pinned cache is protected' : 'Remove cached item',
          onPressed: _working || entry.pinned ? null : () => _remove(item),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .045), borderRadius: BorderRadius.circular(17), border: Border.all(color: Colors.white.withValues(alpha: .06))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: _storageViolet),
      const SizedBox(height: 10),
      Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
    ]),
  );

  Widget _notice(String message, {bool warning = false}) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: (warning ? Colors.orangeAccent : Colors.white).withValues(alpha: .055), borderRadius: BorderRadius.circular(14)),
    child: Text(message, style: TextStyle(color: warning ? Colors.orangeAccent : Colors.white70, height: 1.4, fontSize: 12)),
  );
}
