export interface ReaderProgressSnapshot {
  pageIndex: number;
  scrollRatio: number;
  updatedAt?: string;
}

type ProgressStorage = Pick<Storage, 'getItem' | 'setItem'>;

const emptyProgress = (): ReaderProgressSnapshot => ({ pageIndex: 0, scrollRatio: 0 });

function getBrowserStorage(): ProgressStorage | undefined {
  try {
    if (typeof window === 'undefined') return undefined;
    return window.localStorage;
  } catch {
    return undefined;
  }
}

export function normalizeReaderProgress(value: unknown): ReaderProgressSnapshot {
  if (!value || typeof value !== 'object') return emptyProgress();
  const candidate = value as Record<string, unknown>;
  if (typeof candidate.pageIndex !== 'number' || !Number.isFinite(candidate.pageIndex)) {
    return emptyProgress();
  }

  const ratio = typeof candidate.scrollRatio === 'number' && Number.isFinite(candidate.scrollRatio)
    ? Math.min(1, Math.max(0, candidate.scrollRatio))
    : 0;

  return {
    pageIndex: Math.max(0, Math.floor(candidate.pageIndex)),
    scrollRatio: ratio,
    ...(typeof candidate.updatedAt === 'string' ? { updatedAt: candidate.updatedAt } : {}),
  };
}

export function readReaderProgress(
  key: string,
  storage: ProgressStorage | undefined = getBrowserStorage(),
): ReaderProgressSnapshot {
  if (!storage) return emptyProgress();
  try {
    const raw = storage.getItem(key);
    if (!raw) return emptyProgress();
    return normalizeReaderProgress(JSON.parse(raw));
  } catch {
    // Storage can be disabled, full, or unavailable in some browser contexts.
    return emptyProgress();
  }
}

export function writeReaderProgress(
  key: string,
  progress: ReaderProgressSnapshot,
  storage: ProgressStorage | undefined = getBrowserStorage(),
): boolean {
  if (!storage) return false;
  try {
    const normalized = normalizeReaderProgress(progress);
    storage.setItem(key, JSON.stringify({
      pageIndex: normalized.pageIndex,
      scrollRatio: normalized.scrollRatio,
      updatedAt: new Date().toISOString(),
    }));
    return true;
  } catch {
    // Progress is a convenience; a storage failure must never break reading.
    return false;
  }
}
