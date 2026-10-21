import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_flutter/ui/reader_page.dart';

void main() {
  group('readerImageDecodeWidth', () {
    test('uses device pixel dimensions for normal phone screens', () {
      expect(
        readerImageDecodeWidth(logicalWidth: 400, devicePixelRatio: 3),
        1200,
      );
    });

    test('keeps low-resolution screens above an excessively tiny decode width', () {
      expect(
        readerImageDecodeWidth(logicalWidth: 240, devicePixelRatio: 1),
        480,
      );
    });

    test('caps the bitmap width on huge displays and extreme pixel ratios', () {
      expect(
        readerImageDecodeWidth(logicalWidth: 5000, devicePixelRatio: 4),
        1920,
      );
    });

    test('falls back safely for invalid layout metrics', () {
      expect(
        readerImageDecodeWidth(logicalWidth: double.nan, devicePixelRatio: 3),
        480,
      );
      expect(
        readerImageDecodeWidth(logicalWidth: 400, devicePixelRatio: 0),
        480,
      );
    });
  });
}
