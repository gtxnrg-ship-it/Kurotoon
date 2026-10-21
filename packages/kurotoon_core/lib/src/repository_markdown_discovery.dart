import 'dart:collection';

/// Safe, deterministic discovery of KuroToon-compatible JSON indexes linked
/// from a public repository README. This discovers metadata only; it never
/// treats a Mihon APK/JAR as executable KuroToon code.
class RepositoryMarkdownDiscovery {
  const RepositoryMarkdownDiscovery();

  /// Resolves a repository landing URL to a likely README URL.
  ///
  /// GitHub repository roots are tried on main/master by the network layer.
  /// Direct Markdown URLs are returned unchanged. Other hosts must supply a
  /// README URL explicitly so discovery does not guess arbitrary endpoints.
  Uri? readmeCandidate(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || (uri.hasPort && uri.port != 443) ||
        uri.hasFragment) {
      return null;
    }
    if (uri.host.toLowerCase() != 'github.com') {
      return uri.path.toLowerCase().endsWith('.md') ? uri : null;
    }
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (segments.length < 2) return null;
    final owner = segments[0];
    final repository = segments[1].replaceFirst(RegExp(r'\.git$'), '');
    if (segments.length >= 4 && segments[2] == 'blob') {
      final branch = segments[3];
      final remainder = segments.skip(4).toList();
      if (remainder.isNotEmpty && remainder.last.toLowerCase().endsWith('.md')) {
        return Uri.https('raw.githubusercontent.com', '/$owner/$repository/$branch/${remainder.join('/')}');
      }
    }
    if (segments.length >= 3 && segments[2] == 'tree') {
      final branch = segments.length >= 4 ? segments[3] : 'main';
      return Uri.https('raw.githubusercontent.com', '/$owner/$repository/$branch/README.md');
    }
    if (segments.length == 2) {
      return Uri.https('raw.githubusercontent.com', '/$owner/$repository/main/README.md');
    }
    return null;
  }

  /// Finds index-like JSON links in Markdown, prioritizing known index names.
  /// Links are returned in stable order and duplicates are removed.
  List<Uri> indexLinks(String markdown, {required Uri documentUri}) {
    final candidates = <Uri>[];
    final pattern = RegExp(
      r'(?:\[[^\]]*\]\(\s*<?([^\s)>]+)>?(?:\s+[^)]*)?\)|https?://[^\s<>\x22\x27)]+)',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(markdown)) {
      var raw = match.group(1) ?? match.group(0) ?? '';
      raw = raw.replaceAll('&amp;', '&').replaceFirst(RegExp(r'[.,;]+$'), '');
      if (raw.isEmpty) continue;
      final parsed = Uri.tryParse(raw);
      if (parsed == null) continue;
      var resolved = parsed.isAbsolute ? parsed : documentUri.resolveUri(parsed);
      resolved = _normalizeGitHubBlob(resolved);
      if (resolved.scheme != 'https' || resolved.host.isEmpty ||
          resolved.userInfo.isNotEmpty || (resolved.hasPort && resolved.port != 443) ||
          resolved.hasFragment || !resolved.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      candidates.add(resolved);
    }
    final unique = LinkedHashSet<String>();
    final normalized = <Uri>[];
    for (final uri in candidates) {
      if (unique.add(uri.toString())) normalized.add(uri);
    }
    normalized.sort((a, b) {
      int priority(Uri uri) {
        final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last.toLowerCase();
        if (name == 'index.json' || name == 'index.min.json') return 0;
        if (name.contains('repository') && name.endsWith('.json')) return 1;
        if (name.contains('catalog') && name.endsWith('.json')) return 2;
        return 3;
      }
      final compared = priority(a).compareTo(priority(b));
      return compared == 0 ? a.toString().compareTo(b.toString()) : compared;
    });
    return List.unmodifiable(normalized);
  }

  Uri _normalizeGitHubBlob(Uri uri) {
    if (uri.host.toLowerCase() != 'github.com') return uri;
    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (parts.length < 5 || parts[2] != 'blob') return uri;
    return Uri.https(
      'raw.githubusercontent.com',
      '/${parts[0]}/${parts[1]}/${parts[3]}/${parts.skip(4).join('/')}',
    );
  }
}
