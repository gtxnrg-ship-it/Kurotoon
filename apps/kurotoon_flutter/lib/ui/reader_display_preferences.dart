import 'package:flutter/material.dart';

/// Persisted, conservative display choices that never crop a comic page by
/// default. Values are sanitized when loaded because settings can outlive app
/// versions or be restored from a damaged database.
class ReaderDisplayPreferences {
  const ReaderDisplayPreferences({
    this.fitMode = 'contain',
    this.dimming = 0,
    this.pageGap = 2,
  });

  final String fitMode;
  final double dimming;
  final double pageGap;

  BoxFit get imageFit => switch (fitMode) {
        'width' => BoxFit.fitWidth,
        'height' => BoxFit.fitHeight,
        _ => BoxFit.contain,
      };

  Map<String, Object> toMap() => <String, Object>{
        'fitMode': fitMode,
        'dimming': dimming,
        'pageGap': pageGap,
      };

  factory ReaderDisplayPreferences.fromStored(Object? stored) {
    if (stored is! Map) return const ReaderDisplayPreferences();
    final rawFit = stored['fitMode'];
    final rawDimming = stored['dimming'];
    final rawGap = stored['pageGap'];
    final fitMode = rawFit is String && const {'contain', 'width', 'height'}.contains(rawFit)
        ? rawFit
        : 'contain';
    final dimming = rawDimming is num && rawDimming.isFinite
        ? rawDimming.toDouble().clamp(0.0, 0.65).toDouble()
        : 0.0;
    final pageGap = rawGap is num && rawGap.isFinite
        ? rawGap.toDouble().clamp(0.0, 24.0).toDouble()
        : 2.0;
    return ReaderDisplayPreferences(
      fitMode: fitMode,
      dimming: dimming,
      pageGap: pageGap,
    );
  }
}

/// Opens the same display editor from Me or the active reader. Persistence is
/// intentionally the caller's responsibility so UI state only changes after a
/// successful local settings write.
Future<ReaderDisplayPreferences?> showReaderDisplayPreferences(
  BuildContext context,
  ReaderDisplayPreferences initial,
) {
  return showModalBottomSheet<ReaderDisplayPreferences>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF11182B),
    builder: (sheetContext) {
      var fitMode = initial.fitMode;
      var dimming = initial.dimming;
      var pageGap = initial.pageGap;
      return StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Reader display',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'These settings are local and apply to future chapters. Images are never cropped by default.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  value: fitMode,
                  decoration: const InputDecoration(
                    labelText: 'Image fit',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'contain', child: Text('Fit entire page')),
                    DropdownMenuItem(value: 'width', child: Text('Fit to width')),
                    DropdownMenuItem(value: 'height', child: Text('Fit to height')),
                  ],
                  onChanged: (value) {
                    if (value != null) setSheetState(() => fitMode = value);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: Text('Page dimming')),
                    Text((dimming * 100).round().toString() + '%'),
                  ],
                ),
                Slider(
                  value: dimming,
                  min: 0,
                  max: 0.65,
                  divisions: 13,
                  label: (dimming * 100).round().toString() + '%',
                  onChanged: (value) => setSheetState(() => dimming = value),
                ),
                Row(
                  children: [
                    const Expanded(child: Text('Page gap')),
                    Text(pageGap.round().toString() + ' px'),
                  ],
                ),
                Slider(
                  value: pageGap,
                  min: 0,
                  max: 24,
                  divisions: 12,
                  label: pageGap.round().toString() + ' px',
                  onChanged: (value) => setSheetState(() => pageGap = value),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(
                          ReaderDisplayPreferences(
                            fitMode: fitMode,
                            dimming: dimming,
                            pageGap: pageGap,
                          ),
                        ),
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
