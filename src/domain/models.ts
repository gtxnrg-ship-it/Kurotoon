export type LanguageCode = string;
export type ProviderId = string;
export type WorkId = string;
export type EditionId = string;
export type ChapterId = string;
export type ListingId = string;

export type PublicationStatus = 'ongoing' | 'completed' | 'hiatus' | 'cancelled' | 'unknown';
export type ChapterKind = 'regular' | 'mini' | 'special' | 'extra' | 'season-break' | 'unknown';
export type ComicFormat = 'manga' | 'manhwa' | 'manhua' | 'webtoon' | 'comic' | 'doujin' | 'other';

export interface CreatorReference {
  id?: string;
  name: string;
  role?: 'author' | 'artist' | 'writer' | 'illustrator' | 'translator' | 'other';
  providerId?: ProviderId;
}

export interface Work {
  id: WorkId;
  canonicalTitle: string;
  aliases: string[];
  creatorIds: string[];
  format: ComicFormat | 'unknown';
  publicationStatus: PublicationStatus;
  createdAt: string;
  updatedAt: string;
}

export interface Edition {
  id: EditionId;
  workId: WorkId;
  title: string;
  languageCode?: LanguageCode;
  adaptationKey?: string;
  format: ComicFormat | 'unknown';
  createdAt: string;
}

export interface ProviderListing {
  id: ListingId;
  providerId: ProviderId;
  providerWorkId: string;
  url: string;
  title: string;
  aliases: string[];
  languageCode?: LanguageCode;
  coverUrl?: string;
  description?: string;
  creators: CreatorReference[];
  workId?: WorkId;
  editionId?: EditionId;
  publicationStatus: PublicationStatus;
  lastVerifiedAt?: string;
}

export interface Chapter {
  id: ChapterId;
  editionId: EditionId;
  numberLabel: string;
  sortOrder?: number;
  title?: string;
  kind: ChapterKind;
  volumeLabel?: string;
  publishedAt?: string;
}

export interface ChapterListing {
  id: string;
  chapterId: ChapterId;
  providerId: ProviderId;
  providerChapterId: string;
  url: string;
  title?: string;
  /** Chapter number as supplied by the provider; kept as text to preserve labels such as 12.5 or oneshot. */
  numberLabel?: string;
  volumeLabel?: string;
  sortOrder?: number;
  kind?: ChapterKind;
  languageCode?: LanguageCode;
  pageCount?: number;
  publishedAt?: string;
  lastVerifiedAt?: string;
}

export interface ReadingProgress {
  editionId: EditionId;
  chapterId?: ChapterId;
  chapterListingId?: string;
  pageIndex: number;
  scrollRatio?: number;
  updatedAt: string;
}

export interface LibraryEntry {
  id: string;
  workId: WorkId;
  preferredEditionId?: EditionId;
  status: 'reading' | 'completed' | 'paused' | 'planned' | 'dropped';
  categoryIds: string[];
  addedAt: string;
  updatedAt: string;
}

export type ProviderFailureCode =
  | 'timeout'
  | 'network'
  | 'blocked'
  | 'rate-limited'
  | 'invalid-response'
  | 'unsupported'
  | 'cancelled'
  | 'unknown';

export type ProviderHealthState = 'healthy' | 'degraded' | 'unavailable' | 'unknown';

export interface ProviderHealth {
  providerId: ProviderId;
  state: ProviderHealthState;
  checkedAt: string;
  message?: string;
  consecutiveFailures: number;
}

export interface ProviderFailure {
  providerId: ProviderId;
  code: ProviderFailureCode;
  message: string;
  retryable: boolean;
}

export interface ProviderSearchQuery {
  query: string;
  languageCodes?: LanguageCode[];
  formats?: ComicFormat[];
  limit?: number;
  signal?: AbortSignal;
}

export interface ProviderSearchResult {
  listings: ProviderListing[];
  nextPageToken?: string;
}

export type SearchSourceOutcome =
  | { providerId: ProviderId; status: 'success'; listingIds: ListingId[] }
  | { providerId: ProviderId; status: 'empty' }
  | { providerId: ProviderId; status: 'failed'; failure: ProviderFailure };

export interface UnifiedSearchResult {
  listings: ProviderListing[];
  outcomes: SearchSourceOutcome[];
  isPartial: boolean;
  completedAt: string;
}