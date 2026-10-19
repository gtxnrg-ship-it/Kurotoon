import type { LibraryEntry, ProviderListing } from '../domain/models';
import type { DataStore } from './store';

export type LibraryStatus = LibraryEntry['status'];

export interface SavedSeries {
  id: string;
  listing: ProviderListing;
  status: LibraryStatus;
  categoryIds: string[];
  addedAt: string;
  updatedAt: string;
  sortOrder: number;
  lastReadAt?: string;
}

export interface SavedReadingProgress {
  id: string;
  providerId: string;
  providerWorkId: string;
  providerChapterId: string;
  pageIndex: number;
  scrollRatio: number;
  updatedAt: string;
}

export class LibraryEntryNotFoundError extends Error {
  constructor(id: string) {
    super('The saved series "' + id + '" was not found in the Kurotoon library.');
    this.name = 'LibraryEntryNotFoundError';
  }
}

export function libraryKey(listing: Pick<ProviderListing, 'providerId' | 'providerWorkId'>): string {
  return encodeKey([listing.providerId, listing.providerWorkId]);
}

export function progressKey(input: Pick<SavedReadingProgress, 'providerId' | 'providerWorkId' | 'providerChapterId'>): string {
  return encodeKey([input.providerId, input.providerWorkId, input.providerChapterId]);
}

function encodeKey(parts: string[]): string {
  return parts.map(part => encodeURIComponent(part.trim())).join(':');
}

function assertListing(listing: ProviderListing): void {
  if (!listing.providerId.trim() || !listing.providerWorkId.trim() || !listing.title.trim()) {
    throw new Error('A provider, work identifier, and series title are required to save a series.');
  }
}

function normalizeProgress(value: Partial<SavedReadingProgress>): Omit<SavedReadingProgress, 'id' | 'updatedAt'> {
  const pageIndex = typeof value.pageIndex === 'number' && Number.isFinite(value.pageIndex)
    ? Math.max(0, Math.floor(value.pageIndex))
    : 0;
  const scrollRatio = typeof value.scrollRatio === 'number' && Number.isFinite(value.scrollRatio)
    ? Math.min(1, Math.max(0, value.scrollRatio))
    : 0;
  return {
    providerId: value.providerId ?? '',
    providerWorkId: value.providerWorkId ?? '',
    providerChapterId: value.providerChapterId ?? '',
    pageIndex,
    scrollRatio,
  };
}

export class LibraryRepository {
  constructor(private readonly store: DataStore) {}

  async list(): Promise<SavedSeries[]> {
    const entries = await this.store.list<SavedSeries>('library');
    return entries.map(item => item.value).sort((a, b) =>
      a.sortOrder - b.sortOrder || b.updatedAt.localeCompare(a.updatedAt),
    );
  }

  async get(id: string): Promise<SavedSeries | undefined> {
    return this.store.get<SavedSeries>('library', id);
  }

  async add(listing: ProviderListing, status: LibraryStatus = 'planned'): Promise<SavedSeries> {
    assertListing(listing);
    const id = libraryKey(listing);
    const existing = await this.get(id);
    const timestamp = new Date().toISOString();
    const list = existing ? undefined : await this.list();
    const entry: SavedSeries = {
      id,
      listing,
      status: existing?.status ?? status,
      categoryIds: existing?.categoryIds ?? [],
      addedAt: existing?.addedAt ?? timestamp,
      updatedAt: timestamp,
      sortOrder: existing?.sortOrder ?? list?.length ?? 0,
      ...(existing?.lastReadAt ? { lastReadAt: existing.lastReadAt } : {}),
    };
    await this.store.put('library', id, entry);
    return entry;
  }

  async updateStatus(id: string, status: LibraryStatus): Promise<SavedSeries> {
    const existing = await this.get(id);
    if (!existing) throw new LibraryEntryNotFoundError(id);
    const updated = { ...existing, status, updatedAt: new Date().toISOString() };
    await this.store.put('library', id, updated);
    return updated;
  }

  async setCategories(id: string, categoryIds: string[]): Promise<SavedSeries> {
    const existing = await this.get(id);
    if (!existing) throw new LibraryEntryNotFoundError(id);
    const uniqueIds = [...new Set(categoryIds.map(value => value.trim()).filter(Boolean))];
    const updated = { ...existing, categoryIds: uniqueIds, updatedAt: new Date().toISOString() };
    await this.store.put('library', id, updated);
    return updated;
  }

  async reorder(orderedIds: string[]): Promise<void> {
    // Preserve stable order for items not included in the current reordering action.
    for (const [sortOrder, id] of orderedIds.entries()) {
      const existing = await this.get(id);
      if (!existing) continue;
      await this.store.put('library', id, { ...existing, sortOrder, updatedAt: new Date().toISOString() });
    }
  }

  async markRead(id: string, timestamp = new Date().toISOString()): Promise<void> {
    const existing = await this.get(id);
    if (!existing) return;
    await this.store.put('library', id, {
      ...existing,
      lastReadAt: timestamp,
      status: existing.status === 'planned' ? 'reading' : existing.status,
      updatedAt: timestamp,
    });
  }

  async remove(id: string): Promise<void> {
    await this.store.delete('library', id);
  }
}

export class ProgressRepository {
  constructor(private readonly store: DataStore) {}

  async get(input: Omit<SavedReadingProgress, 'pageIndex' | 'scrollRatio' | 'updatedAt' | 'id'>): Promise<SavedReadingProgress | undefined> {
    return this.store.get<SavedReadingProgress>('progress', progressKey(input));
  }

  async save(input: Partial<SavedReadingProgress> & Pick<SavedReadingProgress, 'providerId' | 'providerWorkId' | 'providerChapterId'>): Promise<SavedReadingProgress> {
    const normalized = normalizeProgress(input);
    if (!normalized.providerId.trim() || !normalized.providerWorkId.trim() || !normalized.providerChapterId.trim()) {
      throw new Error('Provider, work, and chapter identifiers are required to save reading progress.');
    }
    const id = progressKey(normalized);
    const record: SavedReadingProgress = {
      id,
      ...normalized,
      updatedAt: new Date().toISOString(),
    };
    await this.store.put('progress', id, record);
    return record;
  }

  async listForWork(providerId: string, providerWorkId: string): Promise<SavedReadingProgress[]> {
    const prefix = encodeKey([providerId, providerWorkId]) + ':';
    const records = await this.store.list<SavedReadingProgress>('progress');
    return records.map(item => item.value).filter(item => item.id.startsWith(prefix))
      .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  }

  async remove(input: Pick<SavedReadingProgress, 'providerId' | 'providerWorkId' | 'providerChapterId'>): Promise<void> {
    await this.store.delete('progress', progressKey(input));
  }
}

export class SettingsRepository {
  constructor(private readonly store: DataStore) {}

  async get<T>(key: string, fallback: T): Promise<T> {
    const record = await this.store.get<{ value: T }>('settings', key);
    return record ? record.value : fallback;
  }

  async set<T>(key: string, value: T): Promise<void> {
    await this.store.put('settings', key, { value });
  }

  async remove(key: string): Promise<void> {
    await this.store.delete('settings', key);
  }
}

export function createDataRepositories(store: DataStore) {
  return {
    store,
    library: new LibraryRepository(store),
    progress: new ProgressRepository(store),
    settings: new SettingsRepository(store),
  };
}
