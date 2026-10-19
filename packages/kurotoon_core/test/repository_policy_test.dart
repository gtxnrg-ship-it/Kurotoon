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
    ]) {
      expect(policy.validate(url).allowed, isFalse, reason: url);
    }
  });

}
