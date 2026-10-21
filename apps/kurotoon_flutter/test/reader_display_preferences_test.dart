import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_flutter/ui/reader_display_preferences.dart';

void main() {
  group('ReaderDisplayPreferences', () {
    test('round trips supported values', () {
      const original = ReaderDisplayPreferences(
        fitMode: 'width',
        dimming: 0.35,
        pageGap: 12,
      );
      final restored = ReaderDisplayPreferences.fromStored(original.toMap());

      expect(restored.fitMode, 'width');
      expect(restored.dimming, 0.35);
      expect(restored.pageGap, 12);
      expect(restored.imageFit.name, 'fitWidth');
    });

    test('uses safe defaults for malformed settings', () {
      final restored = ReaderDisplayPreferences.fromStored({
        'fitMode': 'cover-and-crop',
        'dimming': 'very dark',
        'pageGap': null,
      });

      expect(restored.fitMode, 'contain');
      expect(restored.dimming, 0);
      expect(restored.pageGap, 2);
      expect(restored.imageFit.name, 'contain');
    });

    test('clamps out-of-range values and rejects non-finite numbers', () {
      final tooLarge = ReaderDisplayPreferences.fromStored({
        'fitMode': 'height',
        'dimming': 9,
        'pageGap': -5,
      });
      final notFinite = ReaderDisplayPreferences.fromStored({
        'dimming': double.nan,
        'pageGap': double.infinity,
      });

      expect(tooLarge.fitMode, 'height');
      expect(tooLarge.dimming, 0.65);
      expect(tooLarge.pageGap, 0);
      expect(notFinite.dimming, 0);
      expect(notFinite.pageGap, 2);
    });

    test('non-map settings safely fall back to defaults', () {
      expect(ReaderDisplayPreferences.fromStored('unexpected').toMap(),
          const ReaderDisplayPreferences().toMap());
      expect(ReaderDisplayPreferences.fromStored(null).toMap(),
          const ReaderDisplayPreferences().toMap());
    });
  });
}
