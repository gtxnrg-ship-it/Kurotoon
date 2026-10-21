import 'package:flutter/material.dart';
import 'package:kurotoon_core/kurotoon_core.dart';

import '../runtime.dart';

const _ink = Color(0xFF080B18);
const _violet = Color(0xFF9D8CFF);
const _cyan = Color(0xFF6EE7F9);

class ProviderDiagnosticsPage extends StatefulWidget {
  const ProviderDiagnosticsPage({super.key, required this.runtime});
  final KurotoonRuntime runtime;

  @override
  State<ProviderDiagnosticsPage> createState() => _ProviderDiagnosticsPageState();
}

class _ProviderDiagnosticsPageState extends State<ProviderDiagnosticsPage> {
  late List<_ProviderRow> _rows;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _rows = _readRows();
  }

  List<_ProviderRow> _readRows() {
    final providers = widget.runtime.providers.all.toList()
      ..sort((a, b) => a.descriptor.name.toLowerCase().compareTo(b.descriptor.name.toLowerCase()));
    return List<_ProviderRow>.unmodifiable(providers.map((provider) {
      final id = provider.descriptor.id;
      return _ProviderRow(
        name: provider.descriptor.name,
        id: id,
        enabled: widget.runtime.providers.isEnabled(id),
        capabilities: provider.descriptor.capabilities.map((item) => item.name).toList()..sort(),
        snapshot: widget.runtime.providerHealth.snapshotFor(id),
        cooldown: widget.runtime.providerHealth.remainingCooldown(id),
      );
    }));
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    // Refresh reads local health state; it never launches unsolicited requests.
    final next = _readRows();
    if (!mounted) return;
    setState(() {
      _rows = next;
      _loading = false;
    });
  }

  String _time(DateTime? value) {
    if (value == null) return 'Not recorded';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _duration(Duration? value) {
    if (value == null || value <= Duration.zero) return 'None';
    if (value.inSeconds < 60) return '${value.inSeconds}s';
    if (value.inMinutes < 60) {
      final seconds = value.inSeconds % 60;
      return seconds == 0 ? '${value.inMinutes}m' : '${value.inMinutes}m ${seconds}s';
    }
    return '${value.inHours}h ${value.inMinutes % 60}m';
  }

  Color _stateColor(ProviderHealthState state) => switch (state) {
        ProviderHealthState.healthy => Colors.greenAccent,
        ProviderHealthState.degraded => const Color(0xFFFFC978),
        ProviderHealthState.coolingDown => _cyan,
      };

  String _stateLabel(ProviderHealthState state) => switch (state) {
        ProviderHealthState.healthy => 'Healthy',
        ProviderHealthState.degraded => 'Degraded',
        ProviderHealthState.coolingDown => 'Cooling down',
      };

  @override
  Widget build(BuildContext context) {
    final enabled = _rows.where((row) => row.enabled).length;
    final degraded = _rows.where((row) => row.snapshot.state == ProviderHealthState.degraded).length;
    final cooling = _rows.where((row) => row.snapshot.state == ProviderHealthState.coolingDown).length;

    return Scaffold(
      backgroundColor: _ink,
      appBar: AppBar(
        title: const Text('Source diagnostics'),
        backgroundColor: const Color(0xFF0B1020),
        actions: [
          IconButton(
            tooltip: 'Refresh local status',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
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
                  const Row(children: [
                    Icon(Icons.health_and_safety_rounded, color: _cyan, size: 28),
                    SizedBox(width: 10),
                    Expanded(child: Text('Your sources, honestly.', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
                  ]),
                  const SizedBox(height: 10),
                  const Text(
                    'Status comes from the local provider health tracker. Refresh does not contact sources, and raw error text is never displayed.',
                    style: TextStyle(color: Colors.white70, height: 1.45, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _summary('Enabled', enabled.toString(), _cyan)),
                    const SizedBox(width: 9),
                    Expanded(child: _summary('Degraded', degraded.toString(), const Color(0xFFFFC978))),
                    const SizedBox(width: 9),
                    Expanded(child: _summary('Cooling', cooling.toString(), _violet)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text('CONNECTED SOURCES',
                style: TextStyle(color: _cyan, letterSpacing: 2.2, fontSize: 11, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            if (_rows.isEmpty) _notice('No providers are registered. Add a supported source from Me → Extensions & repositories.'),
            for (final row in _rows) _providerCard(row),
            const SizedBox(height: 12),
            _notice('Health reflects the latest recorded request, not a live probe. Open Browser and retry a search to test current availability.'),
          ],
        ),
      ),
    );
  }

  Widget _summary(String label, String value, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
        ]),
      );

  Widget _providerCard(_ProviderRow row) {
    final color = _stateColor(row.snapshot.state);
    final lastStatus = row.snapshot.lastStatus?.name ?? 'No request recorded';
    final latest = row.snapshot.lastFailureAt != null &&
            (row.snapshot.lastSuccessAt == null || row.snapshot.lastFailureAt!.isAfter(row.snapshot.lastSuccessAt!))
        ? row.snapshot.lastFailureAt
        : row.snapshot.lastSuccessAt;
    return Card(
      color: Colors.white.withValues(alpha: 0.045),
      margin: const EdgeInsets.only(bottom: 9),
      child: ExpansionTile(
        leading: Icon(row.enabled ? Icons.public_rounded : Icons.public_off_rounded, color: row.enabled ? _cyan : Colors.white38),
        title: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${row.enabled ? 'Enabled' : 'Disabled'} · ${_stateLabel(row.snapshot.state)} · $lastStatus',
            style: TextStyle(color: color, fontSize: 11),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _detail('Provider ID', row.id),
          _detail('Consecutive failures', row.snapshot.consecutiveFailures.toString()),
          _detail('Latest activity', _time(latest)),
          _detail('Last success', _time(row.snapshot.lastSuccessAt)),
          _detail('Last failure', _time(row.snapshot.lastFailureAt)),
          _detail('Remaining cooldown', _duration(row.cooldown)),
          _detail('Capabilities', row.capabilities.isEmpty ? 'None declared' : row.capabilities.join(' · ')),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 132, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11))),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white80, fontSize: 11))),
        ]),
      );

  Widget _notice(String message) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(14)),
        child: Text(message, style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 12)),
      );
}

class _ProviderRow {
  const _ProviderRow({
    required this.name,
    required this.id,
    required this.enabled,
    required this.capabilities,
    required this.snapshot,
    required this.cooldown,
  });

  final String name;
  final String id;
  final bool enabled;
  final List<String> capabilities;
  final ProviderHealthSnapshot snapshot;
  final Duration? cooldown;
}
