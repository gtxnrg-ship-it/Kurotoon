import { describe, expect, it } from 'vitest';
import { MemoryDataStore, openDataStore } from './store';

describe('data store', () => {
  it('stores values in separated durable-data buckets', async () => {
    const store = new MemoryDataStore();
    await store.put('library', 'series-1', { title: 'Series 1' });
    await store.put('progress', 'series-1', { pageIndex: 3 });
    expect(await store.get('library', 'series-1')).toEqual({ title: 'Series 1' });
    expect(await store.get('progress', 'series-1')).toEqual({ pageIndex: 3 });
    expect(await store.list<{ title: string }>('library')).toHaveLength(1);
  });

  it('keeps deletion and cache cleanup scoped to the selected bucket', async () => {
    const store = new MemoryDataStore();
    await store.put('library', 'series-1', { title: 'Series 1' });
    await store.put('catalog', 'series-1', { title: 'Cached metadata' });
    await store.delete('catalog', 'series-1');
    expect(await store.get('catalog', 'series-1')).toBeUndefined();
    expect(await store.get('library', 'series-1')).toEqual({ title: 'Series 1' });
    await store.clear('catalog');
    expect(await store.get('library', 'series-1')).toBeDefined();
  });

  it('makes the non-browser fallback explicitly memory-only', async () => {
    const store = await openDataStore({ factory: null });
    expect(store.mode).toBe('memory');
  });
});
