import { describe, expect, it } from 'vitest';
import { normalizeRepositoryUrl, parseRepositoryIndex } from './registry';

describe('normalizeRepositoryUrl', () => {
  it('accepts a direct HTTPS JSON index and removes its fragment', () => {
    expect(normalizeRepositoryUrl(' https://example.org/repo/index.min.json#copy ')).toBe(
      'https://example.org/repo/index.min.json',
    );
  });

  it('extracts a URL from a Mihon add-repository deep link', () => {
    const encoded = encodeURIComponent('https://example.org/repo/index.min.json');
    expect(normalizeRepositoryUrl('mihon://add-repo?url=' + encoded)).toBe(
      'https://example.org/repo/index.min.json',
    );
  });

  it('rejects non-HTTPS URLs and binary protobuf indexes', () => {
    expect(() => normalizeRepositoryUrl('http://example.org/repo/index.min.json')).toThrow(/HTTPS/);
    expect(() => normalizeRepositoryUrl('https://example.org/repo/index.pb')).toThrow(/binary index\.pb/);
  });

  it('rejects a page URL instead of a direct JSON index', () => {
    expect(() => normalizeRepositoryUrl('https://example.org/repositories')).toThrow(/direct JSON index/);
  });
});

describe('parseRepositoryIndex', () => {
  it('maps Mihon JSON index metadata without exposing download/install actions', () => {
    const result = parseRepositoryIndex([{
      name: 'Sample Source',
      pkg: 'eu.example.source',
      apk: 'sample-source.apk',
      version: '2.4.0',
      lang: 'en',
      nsfw: 1,
      sources: [{ name: 'Sample', lang: 'en', id: '123', baseUrl: 'https://sample.example' }],
    }]);

    expect(result.format).toBe('mihon-json-index');
    expect(result.extensions).toEqual([{
      name: 'Sample Source',
      packageName: 'eu.example.source',
      version: '2.4.0',
      language: 'en',
      contentWarning: true,
      sources: ['Sample · https://sample.example'],
    }]);
    expect(result.extensions[0]).not.toHaveProperty('apk');
  });

  it('accepts an empty index as a valid empty catalogue', () => {
    expect(parseRepositoryIndex([]).extensions).toEqual([]);
  });

  it('rejects unrelated JSON and oversized lists', () => {
    expect(() => parseRepositoryIndex({ extensions: [] })).toThrow(/expected JSON extension list/);
    expect(() => parseRepositoryIndex(Array.from({ length: 10001 }, () => ({})))).toThrow(/too many entries/);
    expect(() => parseRepositoryIndex([{ unexpected: true }])).toThrow(/not a recognised extension index/);
  });
});
