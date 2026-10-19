import { describe, expect, it, vi } from 'vitest';
import type { ProviderListing, ProviderSearchQuery, ProviderSearchResult } from '../domain/models';
import type { ComicProvider } from '../domain/provider';
import { ProviderRegistry } from './registry';

function makeProvider(id: string): ComicProvider {
  return {
    id,
    displayName: id.toUpperCase(),
    version: '1',
    capabilities: { search: true, workDetails: true, chapters: true, chapterPages: true, creatorSearch: false },
    async search(_query: ProviderSearchQuery): Promise<ProviderSearchResult> { return { listings: [] }; },
    async getWorkDetails(providerWorkId: string): Promise<ProviderListing> {
      return {
        id: id + ':' + providerWorkId,
        providerId: id,
        providerWorkId,
        url: 'https://source.example/' + providerWorkId,
        title: providerWorkId,
        aliases: [],
        creators: [],
        publicationStatus: 'unknown',
      };
    },
    async listChapters() { return []; },
    async getChapterPages() { return []; },
    async healthCheck() { return { providerId: id, state: 'healthy', checkedAt: new Date(0).toISOString(), consecutiveFailures: 0 }; },
  };
}

describe('ProviderRegistry', () => {
  it('lists providers deterministically and finds registered adapters', () => {
    const a = makeProvider('z-source');
    const b = makeProvider('a-source');
    const registry = new ProviderRegistry([a, b]);
    expect(registry.list().map(provider => provider.id)).toEqual(['a-source', 'z-source']);
    expect(registry.get('z-source')).toBe(a);
    expect(registry.require('a-source')).toBe(b);
  });

  it('rejects duplicate adapter IDs instead of silently replacing a source', () => {
    const registry = new ProviderRegistry([makeProvider('source')]);
    expect(() => registry.register(makeProvider('source'))).toThrow('already registered');
  });

  it('notifies subscribers when a source becomes available, is updated, or is removed', () => {
    const registry = new ProviderRegistry();
    const listener = vi.fn();
    const unsubscribe = registry.subscribe(listener);
    registry.register(makeProvider('source'));
    registry.replace(makeProvider('source'));
    expect(registry.unregister('source')).toBe(true);
    expect(registry.unregister('source')).toBe(false);
    expect(listener).toHaveBeenCalledTimes(3);
    unsubscribe();
    registry.register(makeProvider('another'));
    expect(listener).toHaveBeenCalledTimes(3);
  });

  it('returns an explicit unsupported error when an adapter is missing', () => {
    const registry = new ProviderRegistry();
    expect(() => registry.require('removed-source')).toThrow(expect.objectContaining({
      providerId: 'removed-source',
      code: 'unsupported',
      retryable: false,
    }));
  });
});
