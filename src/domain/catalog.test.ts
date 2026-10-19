import { describe, expect, it } from 'vitest';
import { groupCatalogListings, rankLatestChapterCandidates } from './catalog';
import type { ProviderListing } from './models';

function listing(overrides: Partial<ProviderListing> & Pick<ProviderListing, 'providerId' | 'providerWorkId' | 'title'>): ProviderListing {
  return {
    id: overrides.providerId + ':' + overrides.providerWorkId,
    providerId: overrides.providerId,
    providerWorkId: overrides.providerWorkId,
    url: 'https://example.test/work/' + overrides.providerWorkId,
    title: overrides.title,
    aliases: overrides.aliases ?? [],
    creators: overrides.creators ?? [],
    publicationStatus: overrides.publicationStatus ?? 'unknown',
    ...overrides,
  };
}

describe('groupCatalogListings', () => {
  it('keeps every source listing while grouping matching external IDs', () => {
    const groups = groupCatalogListings([
      listing({ providerId: 'source-a', providerWorkId: '1', title: 'Moon Keeper', externalIds: { mal: '55' } }),
      listing({ providerId: 'source-b', providerWorkId: '99', title: 'Tsuki no Mamori', externalIds: { mal: '55' } }),
    ]);
    expect(groups).toHaveLength(1);
    expect(groups[0].listings).toHaveLength(2);
    expect(groups[0].aliases).toContain('Tsuki no Mamori');
  });

  it('does not merge same-title listings without creator or external identity evidence', () => {
    const groups = groupCatalogListings([
      listing({ providerId: 'source-a', providerWorkId: '1', title: 'Rebirth' }),
      listing({ providerId: 'source-b', providerWorkId: '2', title: 'Rebirth' }),
    ]);
    expect(groups).toHaveLength(2);
  });

  it('honours explicit user confirmation and rejection', () => {
    const entries = [
      listing({ providerId: 'source-a', providerWorkId: '1', title: 'A Story' }),
      listing({ providerId: 'source-b', providerWorkId: '2', title: 'A Story' }),
    ];
    const keys: [string, string] = ['source-a:1', 'source-b:2'];
    expect(groupCatalogListings(entries, { confirmedPairs: [keys] })).toHaveLength(1);
    expect(groupCatalogListings(entries, { confirmedPairs: [keys], rejectedPairs: [keys] })).toHaveLength(2);
  });

  it('keeps translations and adaptations as source listings, not chapter merges', () => {
    const groups = groupCatalogListings([
      listing({ providerId: 'en-source', providerWorkId: '1', title: 'Moon Keeper', languageCode: 'en', externalIds: { mal: '55' } }),
      listing({ providerId: 'es-source', providerWorkId: '2', title: 'El Guardián Lunar', languageCode: 'es', externalIds: { mal: '55' } }),
    ]);
    expect(groups).toHaveLength(1);
    expect(new Set(groups[0].listings.map((entry) => entry.languageCode))).toEqual(new Set(['en', 'es']));
  });

  it('uses a user-selected canonical title when supplied', () => {
    const entries = [
      listing({ providerId: 'a', providerWorkId: '1', title: 'Moon Keeper', externalIds: { mal: '55' } }),
      listing({ providerId: 'b', providerWorkId: '2', title: 'Tsuki no Mamori', externalIds: { mal: '55' } }),
    ];
    const initial = groupCatalogListings(entries);
    const renamed = groupCatalogListings(entries, { canonicalTitles: { [initial[0].id]: 'Moon Keeper (Universal)' } });
    expect(renamed[0].canonicalTitle).toBe('Moon Keeper (Universal)');
  });
});

describe('rankLatestChapterCandidates', () => {
  it('ranks by verified/published time and retains provider provenance', () => {
    const ranked = rankLatestChapterCandidates([
      { listingId: 'a', providerId: 'slow', chapter: { id: 'a1', chapterId: 'a1', providerId: 'slow', providerChapterId: 'a1', url: 'https://a.test', publishedAt: '2026-01-01T00:00:00Z' } },
      { listingId: 'b', providerId: 'fast', chapter: { id: 'b1', chapterId: 'b1', providerId: 'fast', providerChapterId: 'b1', url: 'https://b.test', publishedAt: '2026-03-01T00:00:00Z' } },
    ]);
    expect(ranked[0].providerId).toBe('fast');
  });
});
