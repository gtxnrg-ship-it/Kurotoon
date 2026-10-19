import { describe, expect, it } from 'vitest';
import type { ProviderListing } from '../domain/models';
import { createDataRepositories, libraryKey, progressKey } from './repositories';
import { MemoryDataStore } from './store';

const listing = (overrides: Partial<ProviderListing> = {}): ProviderListing => ({
  id: 'mangadex:listing:work-1',
  providerId: 'mangadex',
  providerWorkId: 'work-1',
  url: 'https://mangadex.org/title/work-1',
  title: 'The Moon Keeper',
  aliases: ['Moon Keeper'],
  creators: [],
  publicationStatus: 'ongoing',
  ...overrides,
});

describe('local-first application repositories', () => {
  it('uses stable source-scoped identifiers so different provider listings do not collide', () => {
    expect(libraryKey(listing())).toBe(libraryKey(listing()));
    expect(libraryKey(listing({ providerId: 'other-source' }))).not.toBe(libraryKey(listing()));
    expect(progressKey({ providerId: 'mangadex', providerWorkId: 'work-1', providerChapterId: 'chapter:1' }))
      .not.toBe(progressKey({ providerId: 'mangadex', providerWorkId: 'work-1', providerChapterId: 'chapter/1' }));
  });

  it('adds a series, preserves its status and categories on metadata refresh, and removes it', async () => {
    const data = createDataRepositories(new MemoryDataStore());
    const first = await data.library.add(listing(), 'reading');
    expect(first.status).toBe('reading');
    expect((await data.library.list()).map(item => item.id)).toEqual([first.id]);

    await data.library.setCategories(first.id, ['favourites', ' manga ', 'favourites']);
    const refreshed = await data.library.add(listing({ title: 'The Moon Keeper — Revised' }));
    expect(refreshed.status).toBe('reading');
    expect(refreshed.addedAt).toBe(first.addedAt);
    expect(refreshed.listing.title).toBe('The Moon Keeper — Revised');
    expect(refreshed.categoryIds).toEqual(['favourites', 'manga']);

    await data.library.updateStatus(first.id, 'paused');
    expect((await data.library.get(first.id))?.status).toBe('paused');
    await data.library.remove(first.id);
    expect(await data.library.get(first.id)).toBeUndefined();
  });

  it('does not invent a library record if required source identity is missing', async () => {
    const data = createDataRepositories(new MemoryDataStore());
    await expect(data.library.add(listing({ providerWorkId: '' }))).rejects.toThrow('provider, work identifier');
    expect(await data.library.list()).toEqual([]);
  });

  it('keeps progress independent per chapter and clamps malformed positions', async () => {
    const data = createDataRepositories(new MemoryDataStore());
    const first = await data.progress.save({
      providerId: 'mangadex',
      providerWorkId: 'work-1',
      providerChapterId: 'chapter-1',
      pageIndex: 28.9,
      scrollRatio: 2,
    });
    expect(first.pageIndex).toBe(28);
    expect(first.scrollRatio).toBe(1);
    expect((await data.progress.get({
      providerId: 'mangadex',
      providerWorkId: 'work-1',
      providerChapterId: 'chapter-1',
    }))?.pageIndex).toBe(28);

    await data.progress.save({
      providerId: 'mangadex',
      providerWorkId: 'work-1',
      providerChapterId: 'chapter-2',
      pageIndex: -4,
      scrollRatio: -1,
    });
    expect(await data.progress.listForWork('mangadex', 'work-1')).toHaveLength(2);
    expect((await data.progress.listForWork('mangadex', 'work-1')).find(item => item.providerChapterId === 'chapter-2')?.pageIndex).toBe(0);
  });

  it('stores preferences by independent keys and returns provided defaults', async () => {
    const data = createDataRepositories(new MemoryDataStore());
    expect(await data.settings.get('reader.mode', 'paged')).toBe('paged');
    await data.settings.set('reader.mode', 'vertical');
    await data.settings.set('reader.direction', 'rtl');
    expect(await data.settings.get('reader.mode', 'paged')).toBe('vertical');
    expect(await data.settings.get('reader.direction', 'ltr')).toBe('rtl');
    await data.settings.remove('reader.mode');
    expect(await data.settings.get('reader.mode', 'paged')).toBe('paged');
  });

  it('makes memory-only storage mode explicit rather than presenting it as durable', () => {
    expect(new MemoryDataStore().mode).toBe('memory');
  });
});
