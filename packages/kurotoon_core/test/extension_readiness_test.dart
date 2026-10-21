import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

void main() {
  test('marks all four discovery and reading capabilities as reader-ready', () {
    final readiness = ExtensionReadiness.assess(ExtensionCapability.values.where(
      (capability) => capability != ExtensionCapability.creatorWorks,
    ));
    expect(readiness.readerReady, isTrue);
    expect(readiness.missingCapabilities, isEmpty);
    expect(readiness.summary, 'Search + series + chapters + reader');
  });

  test('does not confuse metadata search with a complete reader', () {
    final readiness = ExtensionReadiness.assess([ExtensionCapability.search]);
    expect(readiness.readerReady, isFalse);
    expect(readiness.summary, contains('Metadata/search only'));
    expect(readiness.explanation, contains('chapter listings'));
    expect(readiness.explanation, contains('reader pages'));
  });

  test('supports a useful chapter-only source without claiming discovery', () {
    final readiness = ExtensionReadiness.assess([
      ExtensionCapability.chapterFeed,
      ExtensionCapability.readerPages,
    ]);
    expect(readiness.readerReady, isFalse);
    expect(readiness.summary, 'Chapter reader · no discovery search');
    expect(readiness.missingCapabilities, contains(ExtensionCapability.search));
  });
}
