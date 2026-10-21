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

    final host = uri.host.toLowerCase().replaceAll(RegExp(r'^\[|\]
    if (_isLocalHost(host) || _isPrivateIp(host)) {
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

  bool _isPrivateIp(String host) {
    // IPv4-mapped IPv6 literals can otherwise smuggle a private IPv4 target
    // through code that only checks the IPv6 prefix.
    if (host.startsWith('::ffff:')) return true;

    if (host.contains(':')) {
      // Permit only global-unicast IPv6 literals. This intentionally blocks
      // unspecified, loopback, ULA, link-local, multicast and non-global ranges.
      final first = int.tryParse(host.split(':').first, radix: 16);
      if (first == null || first < 0x2000 || first > 0x3fff) return true;
      // Documentation, Teredo, 6to4 and ORCHID/special-purpose prefixes are
      // not accepted as repository destinations.
      if (host == '::' ||
          host == '::1' ||
          host.startsWith('2001:db8:') || host == '2001:db8' ||
          host.startsWith('2001:0:') || host == '2001:0' ||
          host.startsWith('2002:') || host == '2002' ||
          host.startsWith('2001:10:') || host == '2001:10' ||
          host.startsWith('2001:20:') || host == '2001:20') {
        return true;
      }
      return false;
    }

    // IP parsers in some URL stacks accept legacy non-canonical forms such as
    // 127.1, octal components, or hexadecimal IPv4. Reject numeric-looking
    // address spellings unless all four octets use canonical decimal notation.
    final decimalDotted = RegExp(r'^[0-9.]+$').hasMatch(host);
    final legacyNumeric = RegExp(
      r'^(?:(?:0x[0-9a-f]+|[0-9]+))(?:\.(?:(?:0x[0-9a-f]+|[0-9]+)))*$',
      caseSensitive: false,
    ).hasMatch(host);
    if (!decimalDotted) {
      return legacyNumeric;
    }

    final octets = host.split('.');
    if (octets.length != 4) return true;

    final values = <int>[];
    for (final octet in octets) {
      if (!RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(octet)) return true;
      final value = int.tryParse(octet);
      if (value == null || value < 0 || value > 255) return true;
      values.add(value);
    }

    final a = values[0];
    final b = values[1];
    final third = values[2];
    return a == 0 ||
        a == 10 ||
        a == 127 ||
        a >= 224 ||
        (a == 100 && b >= 64 && b <= 127) ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && (b == 168 || (b == 0 && (third == 0 || third == 2))) ) ||
        (a == 198 && (b == 18 || b == 19 || (b == 51 && third == 100)) ) ||
        (a == 203 && b == 0 && third == 113);
  }

  /// This is only a syntax/literal gate. Network adapters must also validate
  /// every resolved address and redirect destination. DNS lookup and connect
  /// must be treated as separate trust boundaries; this check alone does not
  /// eliminate DNS-rebinding races.
}
), '').replaceFirst(RegExp(r'\.
    if (_isLocalHost(host) || _isPrivateIp(host)) {
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

  bool _isPrivateIp(String host) {
    // IPv4-mapped IPv6 literals can otherwise smuggle a private IPv4 target
    // through code that only checks the IPv6 prefix.
    if (host.startsWith('::ffff:')) return true;

    if (host.contains(':')) {
      // Permit only global-unicast IPv6 literals. This intentionally blocks
      // unspecified, loopback, ULA, link-local, multicast, mapped, transition,
      // and reserved/non-routable ranges rather than trying to enumerate each.
      final first = int.tryParse(host.split(':').first, radix: 16);
      if (first == null || first < 0x2000 || first > 0x3fff) return true;
      if (host == '::' || host == '::1' ||
          host.startsWith('2001:db8:') || host == '2001:db8' ||
          host.startsWith('2001:0:') || host == '2001:0' ||
          host.startsWith('2002:') || host == '2002') {
        return true;
      }
      return false;
    }

    final octets = host.split('.');
    if (octets.length != 4) return false;
    final values = <int>[];
    for (final octet in octets) {
      final value = int.tryParse(octet);
      if (value == null || value < 0 || value > 255) return false;
      values.add(value);
    }

    final a = values[0];
    final b = values[1];
    return a == 0 ||
        a == 10 ||
        a == 127 ||
        a >= 224 ||
        (a == 100 && b >= 64 && b <= 127) ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && (b == 168 || (b == 0 && (values[2] == 0 || values[2] == 2)))) ||
        (a == 198 && (b == 18 || b == 19 || (b == 51 && values[2] == 100))) ||
        (a == 203 && b == 0 && values[2] == 113);
  }

  /// This is only a syntax/literal gate. Network adapters must also validate
  /// every resolved address and redirect destination. DNS lookup and connect
  /// must be treated as separate trust boundaries; this check alone does not
  /// eliminate DNS-rebinding races.
}
), '');
    if (_isLocalHost(host) || _isPrivateIp(host)) {
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

  bool _isPrivateIp(String host) {
    // IPv4-mapped IPv6 literals can otherwise smuggle a private IPv4 target
    // through code that only checks the IPv6 prefix.
    if (host.startsWith('::ffff:')) return true;

    if (host.contains(':')) {
      // Permit only global-unicast IPv6 literals. This intentionally blocks
      // unspecified, loopback, ULA, link-local, multicast, mapped, transition,
      // and reserved/non-routable ranges rather than trying to enumerate each.
      final first = int.tryParse(host.split(':').first, radix: 16);
      if (first == null || first < 0x2000 || first > 0x3fff) return true;
      if (host == '::' || host == '::1' ||
          host.startsWith('2001:db8:') || host == '2001:db8' ||
          host.startsWith('2001:0:') || host == '2001:0' ||
          host.startsWith('2002:') || host == '2002') {
        return true;
      }
      return false;
    }

    final octets = host.split('.');
    if (octets.length != 4) return false;
    final values = <int>[];
    for (final octet in octets) {
      final value = int.tryParse(octet);
      if (value == null || value < 0 || value > 255) return false;
      values.add(value);
    }

    final a = values[0];
    final b = values[1];
    return a == 0 ||
        a == 10 ||
        a == 127 ||
        a >= 224 ||
        (a == 100 && b >= 64 && b <= 127) ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && (b == 168 || (b == 0 && (values[2] == 0 || values[2] == 2)))) ||
        (a == 198 && (b == 18 || b == 19 || (b == 51 && values[2] == 100))) ||
        (a == 203 && b == 0 && values[2] == 113);
  }

  /// This is only a syntax/literal gate. Network adapters must also validate
  /// every resolved address and redirect destination. DNS lookup and connect
  /// must be treated as separate trust boundaries; this check alone does not
  /// eliminate DNS-rebinding races.
}
