import { describe, expect, it } from 'vitest';
import { normalizeReaderProgress, readReaderProgress, writeReaderProgress } from './readerProgress';

function memoryStorage(initial: Record<string, string> = {}) {
  const values = new Map(Object.entries(initial));
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => { values.set(key, value); },
  };
}

describe('reader progress persistence', () => {
  it('defaults missing, malformed, or incomplete records to the chapter start', () => {
    const storage = memoryStorage({ malformed: '{not json', incomplete: JSON.stringify({ scrollRatio: 0.5 }) });
    expect(readReaderProgress('missing', storage)).toEqual({ pageIndex: 0, scrollRatio: 0 });
    expect(readReaderProgress('malformed', storage)).toEqual({ pageIndex: 0, scrollRatio: 0 });
    expect(readReaderProgress('incomplete', storage)).toEqual({ pageIndex: 0, scrollRatio: 0 });
  });

  it('normalizes a valid page index and clamps the scroll ratio', () => {
    expect(normalizeReaderProgress({ pageIndex: 12.8, scrollRatio: 4, updatedAt: 'yesterday' })).toEqual({
      pageIndex: 12,
      scrollRatio: 1,
      updatedAt: 'yesterday',
    });
    expect(normalizeReaderProgress({ pageIndex: -3, scrollRatio: -1 })).toEqual({
      pageIndex: 0,
      scrollRatio: 0,
    });
  });

  it('writes and reads the position without trusting stored values', () => {
    const storage = memoryStorage();
    expect(writeReaderProgress('chapter-a', { pageIndex: 24, scrollRatio: 0.375 }, storage)).toBe(true);
    const restored = readReaderProgress('chapter-a', storage);
    expect(restored.pageIndex).toBe(24);
    expect(restored.scrollRatio).toBe(0.375);
    expect(restored.updatedAt).toBeTruthy();
  });

  it('fails safely if browser storage is unavailable or throws', () => {
    expect(readReaderProgress('chapter-a', undefined)).toEqual({ pageIndex: 0, scrollRatio: 0 });
    const throwingStorage = {
      getItem: () => { throw new Error('blocked'); },
      setItem: () => { throw new Error('quota exceeded'); },
    };
    expect(readReaderProgress('chapter-a', throwingStorage)).toEqual({ pageIndex: 0, scrollRatio: 0 });
    expect(writeReaderProgress('chapter-a', { pageIndex: 1, scrollRatio: 0 }, throwingStorage)).toBe(false);
  });
});
