import 'extension_manifest.dart';

/// A transparent, deterministic assessment of whether a declarative source
/// advertises the minimum capabilities for the full search-to-reader journey.
/// This assesses declared capabilities, not the live health of a remote host.
class ExtensionReadiness {
  const ExtensionReadiness._({
    required this.capabilities,
    required this.missingCapabilities,
  });

  factory ExtensionReadiness.assess(Iterable<ExtensionCapability> values) {
    final capabilities = Set<ExtensionCapability>.unmodifiable(values);
    const required = [
      ExtensionCapability.search,
      ExtensionCapability.seriesDetails,
      ExtensionCapability.chapterFeed,
      ExtensionCapability.readerPages,
    ];
    return ExtensionReadiness._(
      capabilities: capabilities,
      missingCapabilities: List.unmodifiable(required.where((value) => !capabilities.contains(value))),
    );
  }

  final Set<ExtensionCapability> capabilities;
  final List<ExtensionCapability> missingCapabilities;

  bool get readerReady => missingCapabilities.isEmpty;

  String get summary {
    if (readerReady) return 'Search + series + chapters + reader';
    if (capabilities.contains(ExtensionCapability.search) &&
        !capabilities.contains(ExtensionCapability.chapterFeed)) {
      return 'Metadata/search only · cannot read chapters';
    }
    if (capabilities.contains(ExtensionCapability.chapterFeed) &&
        capabilities.contains(ExtensionCapability.readerPages) &&
        !capabilities.contains(ExtensionCapability.search)) {
      return 'Chapter reader · no discovery search';
    }
    final available = <String>[
      if (capabilities.contains(ExtensionCapability.search)) 'search',
      if (capabilities.contains(ExtensionCapability.seriesDetails)) 'series',
      if (capabilities.contains(ExtensionCapability.chapterFeed)) 'chapters',
      if (capabilities.contains(ExtensionCapability.readerPages)) 'reader',
      if (capabilities.contains(ExtensionCapability.creatorWorks)) 'creator works',
    ];
    return available.isEmpty ? 'No supported capabilities' : 'Partial source · ${available.join(' + ')}';
  }

  String get explanation {
    if (readerReady) return 'Advertises the full search-to-reader capability set.';
    if (missingCapabilities.isEmpty) return 'All required reader capabilities are declared.';
    final missing = missingCapabilities.map((value) => switch (value) {
      ExtensionCapability.search => 'search',
      ExtensionCapability.seriesDetails => 'series details',
      ExtensionCapability.chapterFeed => 'chapter listings',
      ExtensionCapability.readerPages => 'reader pages',
      ExtensionCapability.creatorWorks => 'creator works',
    }).toList(growable: false);
    return 'Not a complete reader yet. Missing: ${missing.join(', ')}. '
        'Remote behavior is only confirmed when requests are tested.';
  }
}
