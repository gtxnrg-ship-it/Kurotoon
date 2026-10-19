import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

void main() {
  final baseTime = DateTime.utc(2026, 1, 1);

  ReadingProgress progress({
    required DateTime time,
    required String chapter,
    required double fraction,
    String device = 'device-a',
    int revision = 0,
  }) => ReadingProgress(
        workId: 'work',
        editionId: 'edition',
        chapterId: chapter,
        fraction: fraction,
        updatedAt: time,
        deviceId: device,
        revision: revision,
      );

  test('newer intentional rewind wins over older progress', () {
    final current = progress(time: baseTime, chapter: 'ch-10', fraction: 0.9);
    final incoming = progress(
      time: baseTime.add(const Duration(minutes: 1)),
      chapter: 'ch-3',
      fraction: 0.1,
    );
    expect(mergeProgress(current, incoming).chapterId, 'ch-3');
    expect(mergeProgress(current, incoming).fraction, 0.1);
  });

  test('older synced state cannot overwrite newer state', () {
    final current = progress(time: baseTime.add(const Duration(hours: 2)), chapter: 'ch-10', fraction: 0.4);
    final incoming = progress(time: baseTime, chapter: 'ch-2', fraction: 1);
    expect(mergeProgress(current, incoming).chapterId, 'ch-10');
  });

  test('rejects invalid progress fractions', () {
    expect(
      () => progress(time: baseTime, chapter: 'ch-1', fraction: 1.1),
      throwsArgumentError,
    );
  });
}
