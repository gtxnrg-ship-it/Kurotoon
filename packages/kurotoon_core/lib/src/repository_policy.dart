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
    if (_isLocalHost(host) || _isPrivateIp(host)) {
      return const RepositoryDecision(
        allowed: false,
        reason: 'Local and private-network repository hosts are not allowed',
      );
    }

    return RepositoryDecision(allowed: true, reason: 'URL syntax passed initial safety checks', uri: uri);
  }

  bool _isLocalHost(String host) =>
      host == 'localhost' || host.endsWith('.localhost') || host.endsWith('.local');

  bool _isPrivateIp(String host) {
    if (host == '::' || host == '::1' || host.startsWith('fc') ||
        host.startsWith('fd') || host.startsWith('fe80:')) {
      return true;
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
        (a == 192 && (b == 168 || (b == 0 && (octets[2] == 0 || octets[2] == 2)))) ||
        (a == 198 && (b == 18 || b == 19 || (b == 51 && octets[2] == 100))) ||
        (a == 203 && b == 0 && octets[2] == 113);
  }

  /// This check is only the first gate. Before a request/redirect is followed,
  /// the network adapter must validate the resolved IP address too, to guard
  /// against DNS rebinding and redirects into local/private services.
}
