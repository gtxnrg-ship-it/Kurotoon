import type {
  ChapterListing,
  ProviderHealth,
  ProviderListing,
  ProviderSearchQuery,
  ProviderSearchResult,
  ProviderId,
} from './models';

export interface ProviderCapabilities {
  search: boolean;
  workDetails: boolean;
  chapters: boolean;
  chapterPages: boolean;
  creatorSearch: boolean;
}

export interface ComicProvider {
  readonly id: ProviderId;
  readonly displayName: string;
  readonly version: string;
  readonly capabilities: ProviderCapabilities;

  search(query: ProviderSearchQuery): Promise<ProviderSearchResult>;
  getWorkDetails(providerWorkId: string, signal?: AbortSignal): Promise<ProviderListing>;
  listChapters(providerWorkId: string, signal?: AbortSignal): Promise<ChapterListing[]>;
  getChapterPages(providerChapterId: string, signal?: AbortSignal): Promise<string[]>;
  healthCheck(signal?: AbortSignal): Promise<ProviderHealth>;
}

export class ProviderRequestError extends Error {
  readonly providerId: ProviderId;
  readonly code: 'timeout' | 'network' | 'blocked' | 'rate-limited' | 'invalid-response' | 'unsupported' | 'cancelled' | 'unknown';
  readonly retryable: boolean;

  constructor(options: {
    providerId: ProviderId;
    code: ProviderRequestError['code'];
    message: string;
    retryable?: boolean;
  }) {
    super(options.message);
    this.name = 'ProviderRequestError';
    this.providerId = options.providerId;
    this.code = options.code;
    this.retryable = options.retryable ?? false;
  }
}

export function isProviderRequestError(error: unknown): error is ProviderRequestError {
  return error instanceof ProviderRequestError;
}