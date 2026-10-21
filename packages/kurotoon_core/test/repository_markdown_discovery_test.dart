import 'package:test/test.dart';
import 'package:kurotoon_core/kurotoon_core.dart';

void main() {
  const discovery = RepositoryMarkdownDiscovery();

  test('turns a GitHub repository URL into a raw README candidate', () {
    expect(
      discovery.readmeCandidate('https://github.com/example/catalog'),
      Uri.parse('https://raw.githubusercontent.com/example/catalog/main/README.md'),
    );
  });

  test('normalizes a GitHub README URL to raw content', () {
    expect(
      discovery.readmeCandidate('https://github.com/example/catalog/blob/main/README.md'),
      Uri.parse('https://raw.githubusercontent.com/example/catalog/main/README.md'),
    );
  });

  test('discovers and prioritizes linked index JSON files', () {
    final readme = Uri.parse('https://raw.githubusercontent.com/example/catalog/main/README.md');
    final links = discovery.indexLinks('''
      [Extension manifest](extensions/source.json)
      [Repository index](catalog/index.json)
      [Another index](https://github.com/example/catalog/blob/main/other/index.json)
      [Duplicate](catalog/index.json)
      [Not JSON](https://example.org/readme.md)
    ''', documentUri: readme);

    expect(links, [
      Uri.parse('https://raw.githubusercontent.com/example/catalog/main/catalog/index.json'),
      Uri.parse('https://raw.githubusercontent.com/example/catalog/main/other/index.json'),
      Uri.parse('https://raw.githubusercontent.com/example/catalog/main/extensions/source.json'),
    ]);
  });

  test('rejects non-HTTPS and credential-bearing README URLs', () {
    expect(discovery.readmeCandidate('http://github.com/example/catalog'), isNull);
    expect(discovery.readmeCandidate('https://user:secret@github.com/example/catalog'), isNull);
  });
}
