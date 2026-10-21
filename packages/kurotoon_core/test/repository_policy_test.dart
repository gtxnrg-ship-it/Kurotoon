import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

void main() {
  const policy = RepositoryPolicy();

  test('accepts a public HTTPS repository URL', () {
    final result = policy.validate('https://extensions.example.org/repo.json');
    expect(result.allowed, isTrue);
    expect(result.uri?.scheme, 'https');
  });

  test('rejects non-HTTPS and credential-bearing URLs', () {
    expect(policy.validate('http://extensions.example.org/repo.json').allowed, isFalse);
    expect(policy.validate('https://user:pass@example.org/repo.json').allowed, isFalse);
  });

  test('rejects localhost and common private IPv4 ranges', () {
    for (final url in [
      'https://localhost/repo.json',
      'https://localhost./repo.json',
      'https://foo.localhost/repo.json',
      'https://127.0.0.1/repo.json',
      'https://10.0.0.4/repo.json',
      'https://192.168.1.2/repo.json',
      'https://172.20.0.8/repo.json',
    ]) {
      expect(policy.validate(url).allowed, isFalse, reason: url);
    }
  });

  test('rejects custom ports fragments and additional reserved IPv4 ranges', () {
    expect(policy.validate('https://extensions.example.org:8443/repo.json').allowed, isFalse);
    expect(policy.validate('https://extensions.example.org/repo.json#fragment').allowed, isFalse);
    for (final url in [
      'https://100.64.0.1/repo.json',
      'https://192.0.2.1/repo.json',
      'https://198.18.0.1/repo.json',
      'https://203.0.113.1/repo.json',
      // Legacy URL parsers may reinterpret these as loopback/private IPv4.
      'https://0177.0.0.1/repo.json',
      'https://127.1/repo.json',
      'https://0x7f000001/repo.json',
      'https://0x7f.0.0.1/repo.json',
    ]) {
      expect(policy.validate(url).allowed, isFalse, reason: url);
    }
  });

  test('rejects private and reserved IPv6 repository literals', () {
    for (final url in [
      'https://[::]/repo.json',
      'https://[::1]/repo.json',
      'https://[fc00::1]/repo.json',
      'https://[fd00::1]/repo.json',
      'https://[fe80::1]/repo.json',
      'https://[ff02::1]/repo.json',
      'https://[::ffff:127.0.0.1]/repo.json',
      'https://[::ffff:7f00:1]/repo.json',
      'https://[2001:db8::1]/repo.json',
      'https://[2002:7f00:1::1]/repo.json',
      'https://[2001:0::1]/repo.json',
      'https://[2001:10::1]/repo.json',
      'https://[2001:20::1]/repo.json',
    ]) {
      expect(policy.validate(url).allowed, isFalse, reason: url);
    }
  });

  test('continues to allow canonical public IPv4 addresses', () {
    expect(policy.validate('https://1.2.3.4/repo.json').allowed, isTrue);
  });

  test('allows a public global-unicast IPv6 literal', () {
    expect(policy.validate('https://[2606:4700:4700::1111]/repo.json').allowed, isTrue);
  });
}
