import { describe, expect, it } from 'vitest';
import type { ProviderListing } from '../domain/models';
import {
  buildUniversalCatalog,
  suggestPotentialDuplicates,
  type CatalogListingInput,
} from './universalCatalog';

function listing(input: {
  providerId: string;
  providerWorkId: string;
  title: string;
  languageCode?: string;
  lastVerifiedAt?: string;
  aliases?: string[];
}): ProviderListing {
  return {
    id: input.providerId + ':' + input.providerWorkId,
    providerId: input.providerId,
    providerWorkId: input.providerWorkId,
    url: 'https://example.test/' + input.providerWorkId,
    title: input.title,
    aliases: input.aliases ?? [],
    languageCode: input.languageCode,
    creators: [],
    publicationStatus: 'ongoing',
    lastVerifiedAt: input.lastVerifiedAt,
  };
}

function chapter(input: {
  providerId: string;
  providerWorkId: string;
  providerChapterId: string;
  chapterLabel: string;
  publishedAt?: string;
  lastVerifiedAt?: string;
}) {
  return { ...input, url: 'https://example.test/' + input.providerChapterId };
}

describe('buildUniversalCatalog', () => {
  it('combines identical series from many sources while preserving their listings and aliases', () => {
    const inputs: CatalogListingInput[] = [
      {
        listing: listing({ providerId: 'source-b', providerWorkId: 'moon-2', title: 'Moon Keeper!', languageCode: 'en' }),
        creatorIdentityKeys: ['creator-global-7'],
        latestChapter: chapter({ providerId: 'source-b', providerWorkId: 'moon-2', providerChapterId: 'c2', chapterLabel: '12', publishedAt: '2026-10-14T10:00:00Z' }),
      },
      {
        listing: listing({ providerId: 'source-a', providerWorkId: 'moon-1', title: 'The Moon Keeper', languageCode: 'en' }),
        creatorIdentityKeys: ['creator-global-7'],
        latestChapter: chapter({ providerId: 'source-a', providerWorkId: 'moon-1', providerChapterId: 'c1', chapterLabel: '11', publishedAt: '2026-10-10T10:00:00Z' }),
      },
    ];
    const [result] = buildUniversalCatalog(inputs);
    expect(buildUniversalCatalog(inputs)).toHaveLength(1);
    expect(result.listings).toHaveLength(2);
    expect(result.sourceIds).toEqual(['source-a', 'source-b']);
    expect(result.canonicalTitle).toBe('Moon Keeper!');
    expect(result.aliases).toContain('The Moon Keeper');
    expect(result.latestChapter?.chapterLabel).toBe('12');
    expect(result.latestChapterBasis).toBe('published-at');
  });

  it('merges translated titles only when there is a matching cross-source identity', () => {
    const inputs: CatalogListingInput[] = [
      {
        listing: listing({ providerId: 'source-ko', providerWorkId: 'work-ko', title: '달의 수호자', languageCode: 'ko' }),
        externalIds: { anilist: '9981' },
      },
      {
        listing: listing({ providerId: 'source-en', providerWorkId: 'work-en', title: 'Moon Guardian', languageCode: 'en' }),
        externalIds: { anilist: '9981' },
      },
    ];
    const result = buildUniversalCatalog(inputs);
    expect(result).toHaveLength(1);
    expect(result[0].canonicalTitle).toBe('Moon Guardian');
    expect(result[0].aliases).toContain('달의 수호자');
    expect(result[0].languageCodes).toEqual(['en', 'ko']);
  });

  it('does not merge two unrelated series just because their title is generic and identical', () => {
    const inputs: CatalogListingInput[] = [
      { listing: listing({ providerId: 'a', providerWorkId: 'rebirth-a', title: 'Rebirth' }) },
      { listing: listing({ providerId: 'b', providerWorkId: 'rebirth-b', title: 'Rebirth' }) },
    ];
    expect(buildUniversalCatalog(inputs)).toHaveLength(2);
  });

  it('does not merge listings when an identifier namespace conflicts', () => {
    const inputs: CatalogListingInput[] = [
      {
        listing: listing({ providerId: 'a', providerWorkId: 'same-title-a', title: 'Moon Keeper' }),
        externalIds: { anilist: '100', mal: '500' },
      },
      {
        listing: listing({ providerId: 'b', providerWorkId: 'same-title-b', title: 'Moon Keeper' }),
        externalIds: { anilist: '100', mal: '501' },
      },
    ];
    expect(buildUniversalCatalog(inputs)).toHaveLength(2);
  });

  it('uses normalized title and globally comparable creator evidence for a safe merge', () => {
    const inputs: CatalogListingInput[] = [
      { listing: listing({ providerId: 'a', providerWorkId: 'moon-1', title: 'The Moon Keeper' }), creatorIdentityKeys: ['creator:7'] },
      { listing: listing({ providerId: 'b', providerWorkId: 'moon-2', title: ' the moon keeper! ' }), creatorIdentityKeys: ['CREATOR:7'] },
    ];
    expect(buildUniversalCatalog(inputs)).toHaveLength(1);
  });

  it('uses numeric chapter labels only as fallback when no trustworthy publication dates exist', () => {
    const inputs: CatalogListingInput[] = [
      {
        listing: listing({ providerId: 'a', providerWorkId: 'moon-a', title: 'Moon Keeper' }),
        creatorIdentityKeys: ['creator:7'],
        latestChapter: chapter({ providerId: 'a', providerWorkId: 'moon-a', providerChapterId: 'a12', chapterLabel: '12', lastVerifiedAt: '2026-10-18T12:00:00Z' }),
      },
      {
        listing: listing({ providerId: 'b', providerWorkId: 'moon-b', title: 'Moon Keeper' }),
        creatorIdentityKeys: ['creator:7'],
        latestChapter: chapter({ providerId: 'b', providerWorkId: 'moon-b', providerChapterId: 'b13', chapterLabel: '13', lastVerifiedAt: '2026-10-17T12:00:00Z' }),
      },
    ];
    const [result] = buildUniversalCatalog(inputs);
    expect(result.latestChapter?.chapterLabel).toBe('13');
    expect(result.latestChapterBasis).toBe('chapter-number');
  });

  it('emits review suggestions without silently merging a title-only match', () => {
    const inputs: CatalogListingInput[] = [
      { listing: listing({ providerId: 'a', providerWorkId: 'rb-a', title: 'Rebirth' }) },
      { listing: listing({ providerId: 'b', providerWorkId: 'rb-b', title: ' Rebirth! ' }) },
    ];
    const suggestions = suggestPotentialDuplicates(inputs);
    expect(suggestions).toHaveLength(1);
    expect(suggestions[0].confidence).toBeGreaterThanOrEqual(0.5);
    expect(suggestions[0].leftListingKey).not.toBe(suggestions[0].rightListingKey);
  });

  it('caps review suggestions and per-title comparisons for huge common-title buckets', () => {
    const inputs = Array.from({ length: 100 }, (_, index): CatalogListingInput => ({
      listing: listing({ providerId: 'source-' + index, providerWorkId: 'work-' + index, title: 'Rebirth' }),
    }));
    expect(suggestPotentialDuplicates(inputs, { maxSuggestions: 7, maxPerTitleBucket: 12 })).toHaveLength(7);
    expect(suggestPotentialDuplicates(inputs, { maxSuggestions: 0 })).toHaveLength(0);
  });

  it('scales across a large batch by using title+creator blocks rather than all-pairs matching', () => {
    const inputs = Array.from({ length: 2000 }, (_, index): CatalogListingInput => {
      const work = Math.floor(index / 4);
      return {
        listing: listing({ providerId: 'source-' + (index % 4), providerWorkId: 'work-' + work, title: 'Story ' + work }),
        creatorIdentityKeys: ['creator:' + work],
      };
    });
    const results = buildUniversalCatalog(inputs);
    expect(results).toHaveLength(500);
    expect(results.every(item => item.listings.length === 4)).toBe(true);
  });
});
