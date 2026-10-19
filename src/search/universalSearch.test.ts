import { afterEach, describe, expect, it, vi } from 'vitest';
import type { ProviderListing, ProviderSearchQuery } from '../domain/models';
import type { ComicProvider } from '../domain/provider';
import { ProviderRequestError } from '../domain/provider';
import { searchUniversalCatalog } from './universalSearch';

afterEach(() => {
  vi.useRealTimers();
});

function listing(providerId: string, providerWorkId: string, overrides: Partial<ProviderListing> = {}): ProviderListing {
  return {
    id: providerId + ':' + providerWorkId,
    providerId,
    providerWorkId,
    url: 'https://source.example/title/' + providerWorkId,
    title: providerWorkId,
    aliases: [],
    creators: [],
    publicationStatus: 'ongoing',
    ...overrides,
  };
}

function provider(
  id: string,
  search: (query: ProviderSearchQuery) => Promise<{ listings: ProviderListing[] }>,
  overrides: Partial<Pick<ComicProvider, 'capabilities'>> = {},
): ComicProvider {
  return {
    id,
    displayName: id,
    version: '1.0.0',
    capabilities: {
      search: true,
      workDetails: true,
      chapters: true,
      chapterPages: true,
      creatorSearch: false,
      ...overrides.capabilities,
    },
    search,
    async getWorkDetails(providerWorkId) { return listing(id, providerWorkId); },
    async listChapters() { return []; },
    async getChapterPages() { return []; },
    async healthCheck() {
      return { providerId: id, state: 'healthy', checkedAt: new Date(0).toISOString(), consecutiveFailures: 0 };
    },
  };
}

describe('searchUniversalCatalog', () => {
  it('aggregates provider results and keeps outcomes in provider order', async () => {
    const a = provider('a', async () => ({ listings: [listing('a', 'work-a')] }));
    const b = provider('b', async () => ({ listings: [listing('b', 'work-b')] }));
    const result = await searchUniversalCatalog([a, b], { query: 'moon', limit: 7 }, {
      now: () => new Date('2026-10-19T00:00:00.000Z'),
    });
    expect(result.listings.map(item => item.providerId)).toEqual(['a', 'b']);
    expect(result.outcomes).toEqual([
      { providerId: 'a', status: 'success', listingIds: ['a:work-a'] },
      { providerId: 'b', status: 'success', listingIds: ['b:work-b'] },
    ]);
    expect(result.isPartial).toBe(false);
    expect(result.completedAt).toBe('2026-10-19T00:00:00.000Z');
  });

  it('distinguishes a genuine empty source from a failed source', async () => {
    const empty = provider('empty', async () => ({ listings: [] }));
    const broken = provider('broken', async () => {
      throw new ProviderRequestError({
        providerId: 'broken',
        code: 'rate-limited',
        message: 'Slow down.',
        retryable: true,
      });
    });
    const result = await searchUniversalCatalog([empty, broken], { query: 'moon' });
    expect(result.outcomes[0]).toEqual({ providerId: 'empty', status: 'empty' });
    expect(result.outcomes[1]).toMatchObject({
      providerId: 'broken',
      status: 'failed',
      failure: { providerId: 'broken', code: 'rate-limited', retryable: true },
    });
    expect(result.isPartial).toBe(true);
    expect(result.listings).toEqual([]);
  });

  it('honors an enabled-source allowlist and per-source result limit', async () => {
    const searched = vi.fn(async () => ({ listings: [listing('a', 'work-a')] }));
    const notEnabled = provider('b', searched as never);
    const enabled = provider('a', searched);
    await searchUniversalCatalog([enabled, notEnabled], { query: 'moon' }, {
      enabledProviderIds: ['a'],
      limitPerProvider: 9,
    });
    expect(searched).toHaveBeenCalledTimes(1);
    expect(searched.mock.calls[0][0]).toMatchObject({ query: 'moon', limit: 9 });
  });

  it('refuses listings attributed to a different source', async () => {
    const spoofed = provider('a', async () => ({ listings: [listing('b', 'work-b')] }));
    const result = await searchUniversalCatalog([spoofed], { query: 'moon' });
    expect(result.listings).toEqual([]);
    expect(result.outcomes[0]).toMatchObject({
      providerId: 'a',
      status: 'failed',
      failure: { code: 'invalid-response' },
    });
  });

  it('deduplicates the same provider work and prefers the fresher metadata', async () => {
    const stale = listing('a', 'work-a', { title: 'Old title', lastVerifiedAt: '2026-01-01T00:00:00Z' });
    const fresh = listing('a', 'work-a', { title: 'Fresh title', lastVerifiedAt: '2026-02-01T00:00:00Z' });
    const result = await searchUniversalCatalog([provider('a', async () => ({ listings: [stale, fresh] }))], { query: 'moon' });
    expect(result.listings).toHaveLength(1);
    expect(result.listings[0].title).toBe('Fresh title');
  });

  it('enforces a bounded worker pool', async () => {
    let active = 0;
    let peak = 0;
    const providers = Array.from({ length: 7 }, (_, index) => provider('p' + index, async () => {
      active += 1;
      peak = Math.max(peak, active);
      await new Promise(resolve => setTimeout(resolve, 5));
      active -= 1;
      return { listings: [] };
    }));
    await searchUniversalCatalog(providers, { query: 'moon' }, { maxConcurrency: 2 });
    expect(peak).toBe(2);
  });

  it('times out sources that do not settle even if they ignore AbortSignal', async () => {
    const slow = provider('slow', async () => new Promise(() => undefined));
    const result = await searchUniversalCatalog([slow], { query: 'moon' }, { providerTimeoutMs: 5 });
    expect(result.outcomes[0]).toMatchObject({
      providerId: 'slow',
      status: 'failed',
      failure: { code: 'timeout', retryable: true },
    });
  });

  it('cancels a source that ignores AbortSignal when the caller cancels', async () => {
    const controller = new AbortController();
    const slow = provider('slow', async () => new Promise(() => undefined));
    const pending = searchUniversalCatalog([slow], { query: 'moon' }, { signal: controller.signal, providerTimeoutMs: 5_000 });
    await Promise.resolve();
    controller.abort();
    const result = await pending;
    expect(result.outcomes[0]).toMatchObject({
      providerId: 'slow',
      status: 'failed',
      failure: { code: 'cancelled', retryable: false },
    });
  });

  it('does not claim empty-result success when the source cannot search', async () => {
    const noSearch = provider('no-search', async () => ({ listings: [] }), { capabilities: { search: false } });
    const result = await searchUniversalCatalog([noSearch], { query: 'moon' });
    expect(result.outcomes[0]).toMatchObject({
      providerId: 'no-search',
      status: 'failed',
      failure: { code: 'unsupported' },
    });
  });

  it('returns immediately for whitespace-only queries without contacting sources', async () => {
    const search = vi.fn(async () => ({ listings: [] }));
    const result = await searchUniversalCatalog([provider('a', search)], { query: '  ' });
    expect(search).not.toHaveBeenCalled();
    expect(result).toMatchObject({ listings: [], outcomes: [], isPartial: false });
  });
});
