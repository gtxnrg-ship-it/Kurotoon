import { describe, expect, it } from 'vitest';
import type { ProviderListing } from './models';
import { groupUniversalWorks } from './universalCatalog';

function listing(overrides: Partial<ProviderListing> & Pick<ProviderListing, 'providerId' | 'providerWorkId' | 'title'>): ProviderListing {
  return {
    ...overrides,
    id: overrides.id ?? overrides.providerId + ':listing:' + overrides.providerWorkId,
    url: overrides.url ?? 'https://example.test/' + overrides.providerWorkId,
    aliases: overrides.aliases ?? [],
    creators: overrides.creators ?? [],
    publicationStatus: overrides.publicationStatus ?? 'unknown',
  };
}

describe('groupUniversalWorks', () => {
  it('groups matching source listings when normalized titles and creator evidence agree', () => {
    const result = groupUniversalWorks([
      listing({
        providerId: 'source-a',
        providerWorkId: '42',
        title: 'The Moon Keeper',
        creators: [{ name: 'A. Author', role: 'author', providerId: 'source-a' }],
      }),
      listing({
        providerId: 'source-b',
        providerWorkId: '77',
        title: 'the moon keeper!',
        creators: [{ name: 'A. Author', role: 'author', providerId: 'source-b' }],
      }),
    ]);

    expect(result).toHaveLength(1);
    expect(result[0].listings).toHaveLength(2);
    expect(result[0].providerIds).toEqual(['source-a', 'source-b']);
    expect(result[0].creators).toHaveLength(1);
  });

  it('does not merge title-only collisions', () => {
    const result = groupUniversalWorks([
      listing({ providerId: 'source-a', providerWorkId: '1', title: 'Rebirth' }),
      listing({ providerId: 'source-b', providerWorkId: '2', title: 'Rebirth' }),
    ]);
    expect(result).toHaveLength(2);
  });

  it('merges different translated titles when a namespaced external identifier matches', () => {
    const result = groupUniversalWorks([
      listing({ providerId: 'source-a', providerWorkId: '1', title: 'Tsuki no Mamori', externalIds: { mal: '12345' } }),
      listing({ providerId: 'source-b', providerWorkId: '2', title: 'The Moon Keeper', externalIds: { mal: '12345' } }),
    ]);
    expect(result).toHaveLength(1);
    expect(result[0].aliases).toContain('Tsuki no Mamori');
    expect(result[0].aliases).toContain('The Moon Keeper');
  });

  it('deduplicates repeated records from the same source and work', () => {
    const result = groupUniversalWorks([
      listing({ providerId: 'source-a', providerWorkId: '1', title: 'The Moon Keeper', lastVerifiedAt: '2026-01-01T00:00:00Z' }),
      listing({ providerId: 'source-a', providerWorkId: '1', title: 'Moon Keeper', lastVerifiedAt: '2026-02-01T00:00:00Z' }),
    ]);
    expect(result).toHaveLength(1);
    expect(result[0].listings).toHaveLength(1);
    expect(result[0].listings[0].title).toBe('Moon Keeper');
  });

  it('selects the most recently verified metadata separately from the primary cover route', () => {
    const result = groupUniversalWorks([
      listing({ providerId: 'source-a', providerWorkId: '1', title: 'The Moon Keeper', coverUrl: 'https://img.test/a.jpg', creators: [{ name: 'Author' }], lastVerifiedAt: '2026-01-01T00:00:00Z' }),
      listing({ providerId: 'source-b', providerWorkId: '2', title: 'The Moon Keeper', creators: [{ name: 'Author' }], lastVerifiedAt: '2026-03-01T00:00:00Z' }),
    ]);
    expect(result).toHaveLength(1);
    expect(result[0].primaryListing.providerId).toBe('source-a');
    expect(result[0].mostRecentlyVerifiedListing.providerId).toBe('source-b');
  });

  it('handles large same-title buckets without automatically merging unrelated series', () => {
    const records = Array.from({ length: 5000 }, (_, index) =>
      listing({ providerId: 'source-' + (index % 5), providerWorkId: String(index), title: 'Rebirth' }),
    );
    expect(groupUniversalWorks(records)).toHaveLength(5000);
  });
});
