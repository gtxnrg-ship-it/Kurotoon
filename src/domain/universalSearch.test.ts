import { describe, expect, it, vi } from 'vitest';
import { searchAcrossProviders } from './universalSearch';
import type { ComicProvider } from './provider';
import type { ProviderListing } from './models';

function makeListing(providerId: string, providerWorkId: string, title: string): ProviderListing {
  return {
    id: providerId + ':' + providerWorkId,
    providerId,
    providerWorkId,
    url: 'https://example.test/' + providerWorkId,
    title,
    aliases: [],
    creators: [],
    publicationStatus: 'unknown',
  };
}

function provider(id: string, search: ComicProvider['search']): ComicProvider {
  return {
    id,
    displayName: id,
    version: '1',
    capabilities: { search: true, workDetails: false, chapters: false, chapterPages: false, creatorSearch: false },
    search,
    getWorkDetails: vi.fn(),
    listChapters: vi.fn(),
    getChapterPages: vi.fn(),
    healthCheck: vi.fn(),
  };
}

describe('searchAcrossProviders', () => {
  it('keeps successful source results when another source fails', async () => {
    const healthy = provider('good', vi.fn(async () => ({ listings: [makeListing('good', '1', 'Moon Keeper')] })));
    const broken = provider('broken', vi.fn(async () => { throw new Error('network unavailable'); }));
    const result = await searchAcrossProviders([healthy, broken], { query: ' moon keeper ' });
    expect(result.listings).toHaveLength(1);
    expect(result.listings[0].providerId).toBe('good');
    expect(result.isPartial).toBe(true);
    expect(result.outcomes.find((item) => item.providerId === 'broken')?.status).toBe('failed');
  });

  it('deduplicates repeated provider-work records without merging cross-source listings', async () => {
    const a = provider('a', vi.fn(async () => ({ listings: [
      makeListing('a', '1', 'Moon Keeper'),
      makeListing('a', '1', 'Moon Keeper duplicate'),
    ] })));
    const b = provider('b', vi.fn(async () => ({ listings: [makeListing('b', '2', 'Moon Keeper')] })));
    const result = await searchAcrossProviders([a, b], { query: 'moon' });
    expect(result.listings).toHaveLength(2);
  });

  it('does not call providers that lack search capability or are disabled', async () => {
    const enabled = provider('enabled', vi.fn(async () => ({ listings: [] })));
    const disabled = provider('disabled', vi.fn(async () => ({ listings: [] })));
    const noSearch = provider('no-search', vi.fn(async () => ({ listings: [] })));
    (noSearch.capabilities as { search: boolean }).search = false;
    const result = await searchAcrossProviders([enabled, noSearch], { query: 'test' });
    expect(enabled.search).toHaveBeenCalledTimes(1);
    expect(disabled.search).not.toHaveBeenCalled();
    expect(noSearch.search).not.toHaveBeenCalled();
    expect(result.outcomes).toHaveLength(1);
  });

  it('returns an empty complete result for a blank query', async () => {
    const source = provider('a', vi.fn(async () => ({ listings: [] })));
    const result = await searchAcrossProviders([source], { query: '   ' });
    expect(result.listings).toEqual([]);
    expect(source.search).not.toHaveBeenCalled();
  });
});
