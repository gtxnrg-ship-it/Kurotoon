import type {
  ProviderFailure,
  ProviderListing,
  ProviderSearchQuery,
  ProviderSearchResult,
  SearchSourceOutcome,
  UnifiedSearchResult,
} from './models';
import { isProviderRequestError, type ComicProvider } from './provider';
import { groupUniversalWorks, type UniversalWorkGroup } from './universalCatalog';

export interface UniversalSearchOptions {
  signal?: AbortSignal;
  /** Maximum number of sources queried simultaneously. Defaults to 4. */
  concurrency?: number;
  /** Per-source deadline in milliseconds. Defaults to 12 seconds. */
  timeoutMs?: number;
  /** Maximum results requested from each source. Defaults to 20. */
  limitPerProvider?: number;
}

export interface UniversalSearchResponse extends UnifiedSearchResult {
  groups: UniversalWorkGroup[];
  queriedProviderIds: string[];
}

function makeAbortError(): Error {
  const error = new Error('Universal search was cancelled.');
  error.name = 'AbortError';
  return error;
}

function toFailure(providerId: string, error: unknown, timedOut: boolean): ProviderFailure {
  if (timedOut) {
    return { providerId, code: 'timeout', message: 'The source did not respond before the search deadline.', retryable: true };
  }
  if (isProviderRequestError(error)) {
    return {
      providerId,
      code: error.code,
      message: error.message,
      retryable: error.retryable,
    };
  }
  const name = error instanceof Error ? error.name : '';
  const message = error instanceof Error ? error.message : 'The source returned an unknown error.';
  if (name === 'AbortError') {
    return { providerId, code: 'cancelled', message: 'The source request was cancelled.', retryable: true };
  }
  return { providerId, code: 'network', message, retryable: true };
}

function uniqueListings(providerId: string, result: ProviderSearchResult): ProviderListing[] {
  // A plugin must never be allowed to attribute another provider's URL to itself.
  // Drop misattributed records rather than silently rewriting their source identity.
  return result.listings.filter(listing =>
    listing.providerId === providerId &&
    listing.providerWorkId.trim().length > 0 &&
    listing.title.trim().length > 0,
  );
}

/**
 * Queries enabled source adapters in bounded parallel batches and preserves
 * per-provider outcomes, so one blocked site cannot erase successful results.
 *
 * This service accepts already-registered adapters; repository JSON parsing or
 * Android APK discovery does not automatically make an extension executable.
 */
export async function searchAcrossProviders(
  providers: readonly ComicProvider[],
  queryInput: ProviderSearchQuery,
  options: UniversalSearchOptions = {},
): Promise<UniversalSearchResponse> {
  if (options.signal?.aborted || queryInput.signal?.aborted) throw makeAbortError();
  const query = queryInput.query.trim();
  if (!query) {
    return { listings: [], groups: [], outcomes: [], isPartial: false, completedAt: new Date().toISOString(), queriedProviderIds: [] };
  }

  const concurrency = Math.max(1, Math.min(8, Math.floor(options.concurrency ?? 4)));
  const timeoutMs = Math.max(250, Math.min(60_000, Math.floor(options.timeoutMs ?? 12_000)));
  const limit = Math.max(1, Math.min(100, Math.floor(options.limitPerProvider ?? queryInput.limit ?? 20)));
  const searchable = providers.filter(provider => provider.capabilities.search);
  const outcomes = new Array<SearchSourceOutcome>(searchable.length);
  const allListings: ProviderListing[] = [];
  let nextIndex = 0;

  const runOne = async (provider: ComicProvider, resultIndex: number): Promise<void> => {
    if (options.signal?.aborted || queryInput.signal?.aborted) throw makeAbortError();
    const controller = new AbortController();
    const externalSignals = [options.signal, queryInput.signal].filter((signal): signal is AbortSignal => Boolean(signal));
    const abortFromCaller = () => controller.abort();
    for (const signal of externalSignals) signal.addEventListener('abort', abortFromCaller, { once: true });

    let timedOut = false;
    const timeout = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, timeoutMs);

    try {
      const result = await provider.search({
        ...queryInput,
        query,
        limit,
        signal: controller.signal,
      });
      if (options.signal?.aborted || queryInput.signal?.aborted) throw makeAbortError();
      if (timedOut) {
        outcomes[resultIndex] = { providerId: provider.id, status: 'failed', failure: toFailure(provider.id, new Error('timeout'), true) };
        return;
      }
      const listings = uniqueListings(provider.id, result);
      // A non-empty provider response containing only invalid records is a source error,
      // not a successful "no results" response.
      if (result.listings.length > 0 && listings.length === 0) {
        outcomes[resultIndex] = {
          providerId: provider.id,
          status: 'failed',
          failure: { providerId: provider.id, code: 'invalid-response', message: 'The source returned listings with missing or mismatched source identity.', retryable: false },
        };
        return;
      }
      allListings.push(...listings);
      outcomes[resultIndex] = listings.length
        ? { providerId: provider.id, status: 'success', listingIds: listings.map(listing => listing.id) }
        : { providerId: provider.id, status: 'empty' };
    } catch (error) {
      if (options.signal?.aborted || queryInput.signal?.aborted) throw makeAbortError();
      outcomes[resultIndex] = {
        providerId: provider.id,
        status: 'failed',
        failure: toFailure(provider.id, error, timedOut),
      };
    } finally {
      clearTimeout(timeout);
      for (const signal of externalSignals) signal.removeEventListener('abort', abortFromCaller);
    }
  };

  const worker = async (): Promise<void> => {
    while (true) {
      if (options.signal?.aborted || queryInput.signal?.aborted) throw makeAbortError();
      const index = nextIndex;
      nextIndex += 1;
      if (index >= searchable.length) return;
      await runOne(searchable[index], index);
    }
  };

  await Promise.all(Array.from({ length: Math.min(concurrency, searchable.length) }, () => worker()));
  if (options.signal?.aborted || queryInput.signal?.aborted) throw makeAbortError();

  const listings = allListings;
  const stableOutcomes = outcomes.filter((outcome): outcome is SearchSourceOutcome => Boolean(outcome));
  return {
    listings,
    groups: groupUniversalWorks(listings),
    outcomes: stableOutcomes,
    isPartial: stableOutcomes.some(outcome => outcome.status === 'failed'),
    completedAt: new Date().toISOString(),
    queriedProviderIds: searchable.map(provider => provider.id),
  };
}
