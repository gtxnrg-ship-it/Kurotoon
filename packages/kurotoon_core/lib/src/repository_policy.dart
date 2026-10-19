class RepositoryDecision {
  const RepositoryDecision({required this.allowed, required this.reason, this.uri});

  final bool allowed;
  final String reason;
  final Uri? uri;
}

class RepositoryPolicy {
  const RepositoryPolicy();

  RepositoryDecision validate(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return const RepositoryDecision(allowed: false, reason: 'URL is empty');

    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.isAbsolute || uri.host.isEmpty) {
      return const RepositoryDecision(allowed: false, reason: 'A valid absolute URL is required');
    }
    if (uri.scheme.toLowerCase() != 'https') {
      return const RepositoryDecision(allowed: false, reason: 'Repositories must use HTTPS');
    }
    if (uri.userInfo.isNotEmpty) {
      return const RepositoryDecision(allowed: false, reason: 'URLs with embedded credentials are not allowed');
    }
    if ((uri.hasPort && uri.port != 443) || uri.hasFragment) {
      return const RepositoryDecision(allowed: false, reason: 'Repositories must use HTTPS on the default port without fragments');
    }

    final host = uri.host.toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
    if (_isLocalHost(host) || _isNonPublicIpLiteral(host)) {
      return const RepositoryDecision(
        allowed: false,
        reason: 'Local, reserved, and private-network repository hosts are not allowed',
      );
    }

    return RepositoryDecision(allowed: true, reason: 'URL syntax passed initial safety checks', uri: uri);
  }

  bool _isLocalHost(String host) {
    final normalized = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    return normalized == 'localhost' ||
        normalized.endsWith('.localhost') ||
        normalized.endsWith('.local');
  }

  bool _isNonPublicIpLiteral(String host) {
    // IPv4-mapped IPv6 can otherwise hide a private IPv4 destination.
    if (host.startsWith('::ffff:')) return true;

    if (host.contains(':')) {
      // For an IPv6 literal, permit only global-unicast 2000::/3. This is a
      // conservative URL-policy check, not a replacement for DNS validation.
      final firstHextet = int.tryParse(host.split(':').first, radix: 16);
      if (firstHextet == null || firstHextet < 0x2000 || firstHextet > 0x3fff) {
        return true;
      }
      // Reject documentation, Teredo, 6to4 and ORCHID/special-purpose ranges.
      if (host == '::' ||
          host == '::1' ||
          host.startsWith('2001:db8:') ||
          host == '2001:db8' ||
          host.startsWith('2001:0:') ||
          host == '2001:0' ||
          host.startsWith('2002:') ||
          host == '2002' ||
          host.startsWith('2001:10:') ||
          host == '2001:10' ||
          host.startsWith('2001:20:') ||
          host == '2001:20') {
        return true;
      }
      return false;
    }

    final octets = host.split('.');
    if (octets.length != 4) return false;
    final values = <int>[];
    for (final octet in octets) {
      // Reject non-canonical numeric forms rather than letting URL parsers
      // interpret octal/short/packed address spellings inconsistently.
      if (!RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(octet)) return true;
      final value = int.tryParse(octet);
      if (value == null || value < 0 || value > 255) return true;
      values.add(value);
    }

    final a = values[0];
    final b = values[1];
    final c = values[2];
    return a == 0 ||
        a == 10 ||
        a == 127 ||
        a >= 224 ||
        (a == 100 && b >= 64 && b <= 127) ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && (b == 168 || (b == 0 && (c == 0 || c == 2)))) ||
        (a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100))) ||
        (a == 203 && b == 0 && c == 113);
  }

  /// This literal gate is only the first boundary. Before every request or
  /// redirect, the network adapter must validate resolved addresses and must
  /// reject non-public destinations. DNS lookup and connect are separate
  /// trust boundaries, so this method alone cannot eliminate rebinding races.
}
