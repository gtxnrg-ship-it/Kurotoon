import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:test/test.dart';

ReaderPageManifest manifest({
  Uri? baseUrl,
  String hash = 'a1b2c3d4e5f6',
  List<String> filenames = const ['001.webp'],
}) =>
    ReaderPageManifest(
      chapterId: 'chapter-1',
      baseUrl: baseUrl ?? Uri.https('cdn.example.org'),
      hash: hash,
      normalFilenames: filenames,
      dataSaverFilenames: const ['001-small.webp'],
    );

void main() {
  test('constructs HTTPS page URLs with a safe path token', () {
    expect(
      manifest().urls().single.toString(),
      'https://cdn.example.org/data/a1b2c3d4e5f6/001.webp',
    );
  });

  test('rejects path traversal tokens in manifest hashes', () {
    for (final hash in ['../private', 'a/b', r'a\b', '%2e%2e', '']) {
      expect(
        () => manifest(hash: hash),
        throwsArgumentError,
        reason: 'Unsafe page hash should be rejected: $hash',
      );
    }
  });

  test('rejects encoded or explicit traversal in a base URL path', () {
    for (final baseUrl in [
      Uri.parse('https://cdn.example.org/root/../private'),
      Uri.parse('https://cdn.example.org/%2e%2e/private'),
      Uri.parse('https://cdn.example.org/root%2F..%2Fprivate'),
    ]) {
      expect(
        () => manifest(baseUrl: baseUrl),
        throwsArgumentError,
        reason: 'Unsafe base path should be rejected: $baseUrl',
      );
    }
  });

  test('rejects credentials, query strings, fragments and non-default ports', () {
    for (final baseUrl in [
      Uri.parse('https://user@cdn.example.org'),
      Uri.parse('https://cdn.example.org/?token=secret'),
      Uri.parse('https://cdn.example.org/#fragment'),
      Uri.parse('https://cdn.example.org:8443'),
    ]) {
      expect(
        () => manifest(baseUrl: baseUrl),
        throwsArgumentError,
        reason: 'Unclean base URL should be rejected: $baseUrl',
      );
    }
  });

  test('rejects slash and backslash characters in filename segments', () {
    final backslash = String.fromCharCode(92);
    for (final name in ['../private.webp', 'folder/page.webp', 'folder${backslash}page.webp', '']) {
      expect(
        () => manifest(filenames: [name]),
        throwsArgumentError,
        reason: 'Unsafe filename should be rejected: $name',
      );
    }
  });

  test('data saver falls back to full-size page set when no saver files exist', () {
    final value = manifest();
    expect(value.urls(dataSaver: true), hasLength(1));
    expect(value.urls(dataSaver: true).single.path, '/data-saver/a1b2c3d4e5f6/001-small.webp');
  });
}
