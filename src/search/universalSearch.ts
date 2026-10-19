import type {
  ProviderFailure,
  ProviderListing,
  ProviderSearchQuery,
  ProviderSearchResult,
  SearchSourceOutcome,
  UnifiedSearchResult,
} from '../domain/models';
import { isProviderRequestError, type ComicProvider } from '../domain/provider';

export interface UniversalSearchOptions {
  /** Filter to enabled source IDs. An omitted filter means all supplied providers. */
  enabledProviderIds?: string[];
  /** Maximum number of providers searched at once. Defaults to four. */
  maxConcurrency?: number;
  /** Per-provider deadline in milliseconds. Defaults to 15 seconds. */
  providerTimeoutMs?: number;
  /** Result limit requested from each provider. Defaults to twenty. */
  limitPerProvider?: number;
  /** Cancellation signal for the complete search operation. */
  signal?: AbortSignal;
  /** Injectable clock for deterministic tests. */
  now?: () => Date;
}

interface CompletedSource {
  listings: ProviderListing[];
  outcome: SearchSourceOutcome;
}

const DEFAULT_CONCURRENCY = 4;
const MAX_CONCURRENCY = 8;
const DEFAULT_TIMEOUT_MS = 15_000;
const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;
const MAX_ERROR_LENGTH = 240;

function boundedInteger(value: number | undefined, fallback: number, min: number, max: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return fallback;
  return Math.min(max, Math.max(min, Math.floor(value)));
}

function shortMessage(value: string): string {
  const clean = value.replace(/\s+/g, ' ').trim();
  return clean.length > MAX_ERROR_LENGTH ? clean.slice(0, MAX_ERROR_LENGTH - 1) + '…' : clean;
}

function failure(
  providerId: string,
  code: ProviderFailure['code'],
  message: string,
  retryable: boolean,
): SearchSourceOutcome {
  return {
    providerId,
    status: 'failed',
    failure: {
      providerId,
      code,
      message: shortMessage(message),
      retryable,
    },
  };
}

function failedOutcome(provider: ComicProvider, error: unknown, parentSignal?: AbortSignal): SearchSourceOutcome {
  if (parentSignal?.aborted) {
    return failure(provider.id, 'cancelled', 'Search was cancelled.', false);
  }
  if (isProviderRequestError(error)) {
    return failure(provider.id, error.code, error.message, error.retryable);
  }
  if (error instanceof TypeError) {
    return failure(provider.id, 'network', error.message || 'The source could not be reached.', true);
  }
  return failure(
    provider.id,
    'unknown',
    error instanceof Error ? error.message : 'The source search failed for an unknown reason.',
    false,
  );
}

function validListing(listing: unknown, providerId: string): listing is ProviderListing {
  if (typeof listing !== 'object' || listing === null || Array.isArray(listing)) return false;
  const value = listing as Partial<ProviderListing>;
  if (
    value.providerId !== providerId ||
    typeof value.id !== 'string' || !value.id.trim() ||
    typeof value.providerWorkId !== 'string' || !value.providerWorkId.trim() ||
    typeof value.title !== 'string' || !value.title.trim() ||
    typeof value.url !== 'string'
  ) return false;
  try {
    const url = new URL(value.url);
    return (url.protocol === 'https:' || url.protocol === 'http:') &&
      Boolean(url.hostname) && !url.username && !url.password;
  } catch {
    return false;
  }
}

function verifiedTimestamp(listing: ProviderListing): number {
  if (!listing.lastVerifiedAt) return -Infinity;
  const timestamp = Date.parse(listing.lastVerifiedAt);
  return Number.isFinite(timestamp) ? timestamp : -Infinity;
}

/** Deduplicates duplicate rows from one source without collapsing distinct sources. */
function uniqueListings(listings: ProviderListing[]): ProviderListing[] {
  const result: ProviderListing[] = [];
  const positionByWork = new Map<string, number>();
  for (const listing of listings) {
    const key = listing.providerId + '\u001f' + listing.providerWorkId;
    const existingIndex = positionByWork.get(key);
    if (existingIndex === undefined) {
      positionByWork.set(key, result.length);
      result.push(listing);
      continue;
    }
    if (verifiedTimestamp(listing) > verifiedTimestamp(result[existingIndex])) {
      result[existingIndex] = listing;
    }
  }
  return result;
}

async function searchOneProvider(
  provider: ComicProvider,
  searchText: string,
  query: ProviderSearchQuery,
  limit: number,
  timeoutMs: number,
  parentSignal?: AbortSignal,
): Promise<CompletedSource> {
  if (!provider.capabilities.search) {
    return {
      listings: [],
      outcome: failure(provider.id, 'unsupported', 'This source does not support search.', false),
    };
  }
  if (parentSignal?.aborted) {
    return {
      listings: [],
      outcome: failure(provider.id, 'cancelled', 'Search was cancelled.', false),
    };
  }

  const controller = new AbortController();
  let timedOut = false;
  let rejectInterruption: ((reason: unknown) => void) | undefined;
  const interruption = new Promise<never>((_, reject) => { rejectInterruption = reject; });
  const interruptForCancellation = () => {
    controller.abort();
    rejectInterruption?.(new DOMException('Search cancelled.', 'AbortError'));
  };
  if (parentSignal) parentSignal.addEventListener('abort', interruptForCancellation, { once: true });

  const timeout = setTimeout(() => {
    timedOut = true;
    controller.abort();
    rejectInterruption?.(new Error('Provider search timed out.'));
  }, timeoutMs);

  try {
    const request: ProviderSearchQuery = {
      ...query,
      query: searchText,
      limit,
      signal: controller.signal,
    };
    const response: ProviderSearchResult = await Promise.race([
      provider.search(request),
      interruption,
    ]);

    if (!response || typeof response !== 'object' || !Array.isArray(response.listings)) {
      return {
        listings: [],
        outcome: failure(provider.id, 'invalid-response', 'The source returned an invalid search response.', false),
      };
    }
    if (!response.listings.every(listing => validListing(listing, provider.id))) {
      return {
        listings: [],
        outcome: failure(
          provider.id,
          'invalid-response',
          'The source returned a listing with invalid fields, URL, or source attribution.',
          false,
        ),
      };
    }

    const listings = uniqueListings(response.listings);
    return {
      listings,
      outcome: listings.length
        ? { providerId: provider.id, status: 'success', listingIds: listings.map(listing => listing.id) }
        : { providerId: provider.id, status: 'empty' },
    };
  } catch (error) {
    if (timedOut) {
      return {
        listings: [],
        outcome: failure(provider.id, 'timeout', 'The source did not finish searching before its time limit.', true),
      };
    }
    return {
      listings: [],
      outcome: failedOutcome(provider, error, parentSignal),
    };
  } finally {
    clearTimeout(timeout);
    parentSignal?.removeEventListener('abort', interruptForCancellation);
  }
}

/**
 * Searches enabled providers with a bounded worker pool.
 *
 * Results and outcomes remain in supplied provider order, regardless of which
 * network request finishes first. A failed source is never misreported as an
 * empty result, and one provider cannot claim another provider's listings.
 */
export async function searchUniversalCatalog(
  providers: ComicProvider[],
  query: ProviderSearchQuery,
  options: UniversalSearchOptions = {},
): Promise<UnifiedSearchResult> {
  const searchText = query.query.trim();
  const parentSignal = options.signal ?? query.signal;
  const now = options.now ?? (() => new Date());
  if (!searchText) {
    return { listings: [], outcomes: [], isPartial: false, completedAt: now().toISOString() };
  }

  const enabledIds = options.enabledProviderIds ? new Set(options.enabledProviderIds) : undefined;
  const selectedProviders = providers.filter(provider => !enabledIds || enabledIds.has(provider.id));
  const limit = boundedInteger(options.limitPerProvider ?? query.limit, DEFAULT_LIMIT, 1, MAX_LIMIT);
  const concurrency = boundedInteger(options.maxConcurrency, DEFAULT_CONCURRENCY, 1, MAX_CONCURRENCY);
  const timeoutMs = boundedInteger(options.providerTimeoutMs, DEFAULT_TIMEOUT_MS, 1, 120_000);
  const completed: Array<CompletedSource | undefined> = new Array(selectedProviders.length);
  let nextIndex = 0;

  async function worker(): Promise<void> {
    while (true) {
      const index = nextIndex;
      nextIndex += 1;
      if (index >= selectedProviders.length) return;
      completed[index] = await searchOneProvider(
        selectedProviders[index],
        searchText,
        query,
        limit,
        timeoutMs,
        parentSignal,
      );
    }
  }

  const workerCount = Math.min(concurrency, selectedProviders.length);
  await Promise.all(Array.from({ length: workerCount }, () => worker()));

  const sources = completed.filter((value): value is CompletedSource => value !== undefined);
  const listings = sources.flatMap(source => source.listings);
  const outcomes = sources.map(source => source.outcome);
  return {
    listings,
    outcomes,
    isPartial: outcomes.some(outcome => outcome.status === 'failed'),
    completedAt: now().toISOString(),
  };
}
