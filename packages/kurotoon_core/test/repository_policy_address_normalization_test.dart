import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

void main() {
  const policy = RepositoryPolicy();

  test('rejects legacy numeric host formats that may resolve to local IPv4', () {
    for (final host in [
      '0177.0.0.1',
      '127.1',
      '0x7f000001',
      '0x7f.0.0.1',
      '999.1.1.1',
      '1.2.3.4.',
    ]) {
      expect(policy.validate('https://$host/repo.json').allowed, isFalse, reason: host);
    }
  });

  test('rejects IPv6 transition, documentation and ORCHID ranges', () {
    for (final host in [
      '[::ffff:127.0.0.1]',
      '[::ffff:7f00:1]',
      '[2001:db8::1]',
      '[2001:0::1]',
      '[2002:7f00:1::1]',
      '[2001:10::1]',
      '[2001:20::1]',
    ]) {
      expect(policy.validate('https://$host/repo.json').allowed, isFalse, reason: host);
    }
  });

  test('normalizes a trailing dot before checking local hostnames', () {
    expect(policy.validate('https://localhost./repo.json').allowed, isFalse);
  });
}
