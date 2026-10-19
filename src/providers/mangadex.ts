import type {
  ChapterListing,
  ProviderHealth,
  ProviderListing,
  ProviderSearchQuery,
  ProviderSearchResult,
} from '../domain/models';
import { ProviderRequestError, type ComicProvider } from '../domain/provider';

const API = 'https://api.mangadex.org';
const CDN = 'https://uploads.mangadex.org';
const REQUEST_TIMEOUT_MS = 12_000;
const MAX_CHAPTER_PAGES = 5;
const PAGE_SIZE = 100;

type Relationship = { id?: string; type?: string; attributes?: { name?: string; fileName?: string } };
type MangaRecord = {
  id: string;
  attributes?: {
    title?: Record<string, string>;
    altTitles?: Array<Record<string, string>>;
    description?: Record<string, string>;
    status?: string;
    originalLanguage?: string;
    contentRating?: string;
    year?: number;
  };
  relationships?: Relationship[];
};
type ChapterRecord = {
  id: string;
  attributes?: {
    chapter?: string | null;
    title?: string | null;
    volume?: string | null;
    translatedLanguage?: string;
    publishAt?: string;
    pages?: number;
  };
};
type ApiResponse<T> = { result?: string; data?: T[]; total?: number; errors?: Array<{ title?: string; detail?: string }> };
type AtHomeResponse = {
  baseUrl?: string;
  chapter?: { hash?: string; data?: string[]; dataSaver?: string[] };
};

function bestTitle(titles?: Record<string, string>): string {
  if (!titles) return 'Untitled series';
  return titles.en || titles['ja-ro'] || titles.ja || titles.ko || titles['zh-ro'] || titles.zh || Object.values(titles).find(Boolean) || 'Untitled series';
}
function aliasesOf(record: MangaRecord): string[] {
  const aliases = (record.attributes?.altTitles ?? []).flatMap(item => Object.values(item));
  const main = Object.values(record.attributes?.title ?? {});
  return [...new Set([...aliases, ...main].filter(Boolean))];
}
function coverOf(record: MangaRecord): string | undefined {
  const cover = record.relationships?.find(relation => relation.type === 'cover_art')?.attributes?.fileName;
  return cover ? `${CDN}/covers/${record.id}/${encodeURIComponent(cover)}.256.jpg` : undefined;
}
function creatorsOf(record: MangaRecord) {
  return (record.relationships ?? [])
    .filter(relation => relation.type === 'author' || relation.type === 'artist')
    .filter(relation => Boolean(relation.attributes?.name))
    .map(relation => ({
      id: relation.id,
      name: relation.attributes!.name!,
      role: relation.type === 'author' ? 'author' as const : 'artist' as const,
      providerId: 'mangadex',
    }));
}
function publicationStatus(status?: string): ProviderListing['publicationStatus'] {
  if (status === 'ongoing' || status === 'completed' || status === 'hiatus' || status === 'cancelled') return status;
  return 'unknown';
}
function toListing(record: MangaRecord): ProviderListing {
  const attributes = record.attributes ?? {};
  return {
    id: `mangadex:listing:${record.id}`,
    providerId: 'mangadex',
    providerWorkId: record.id,
    url: `https://mangadex.org/title/${record.id}`,
    title: bestTitle(attributes.title),
    aliases: aliasesOf(record),
    coverUrl: coverOf(record),
    description: attributes.description?.en || Object.values(attributes.description ?? {}).find(Boolean),
    creators: creatorsOf(record),
    publicationStatus: publicationStatus(attributes.status),
    lastVerifiedAt: new Date().toISOString(),
  };
}
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

export class MangaDexProvider implements ComicProvider {
  readonly id = 'mangadex';
  readonly displayName = 'MangaDex';
  readonly version = '1';
  readonly capabilities = {
    search: true,
    workDetails: true,
    chapters: true,
    chapterPages: true,
    creatorSearch: false,
  };

  private async request<T>(path: string, signal?: AbortSignal): Promise<T> {
    const controller = new AbortController();
    const abortFromCaller = () => controller.abort(signal?.reason);
    if (signal?.aborted) abortFromCaller();
    else signal?.addEventListener('abort', abortFromCaller, { once: true });

    const timeout = setTimeout(() => controller.abort(new Error('Provider request timed out')), REQUEST_TIMEOUT_MS);
    try {
      const response = await fetch(`${API}${path}`, {
        signal: controller.signal,
        headers: { Accept: 'application/json' },
      });
      if (response.status === 429) {
        throw new ProviderRequestError({ providerId: this.id, code: 'rate-limited', message: 'MangaDex rate limit reached. Please wait before trying again.', retryable: true });
      }
      if (response.status === 403 || response.status === 451) {
        throw new ProviderRequestError({ providerId: this.id, code: 'blocked', message: 'MangaDex did not allow this request.', retryable: false });
      }
      if (!response.ok) {
        throw new ProviderRequestError({
          providerId: this.id,
          code: 'network',
          message: `MangaDex request failed (HTTP ${response.status}).`,
          retryable: response.status >= 500,
        });
      }
      const body: unknown = await response.json();
      // MangaDex API endpoints usually include "result", but its At-Home endpoint
      // returns { baseUrl, chapter } without that envelope field.
      if (!isRecord(body)) {
        throw new ProviderRequestError({ providerId: this.id, code: 'invalid-response', message: 'MangaDex returned an unexpected response.', retryable: false });
      }
      return body as T;
    } catch (error) {
      if (error instanceof ProviderRequestError) throw error;
      if (controller.signal.aborted) {
        const cancelledByCaller = signal?.aborted;
        throw new ProviderRequestError({
          providerId: this.id,
          code: cancelledByCaller ? 'cancelled' : 'timeout',
          message: cancelledByCaller ? 'The MangaDex request was cancelled.' : 'MangaDex took too long to respond.',
          retryable: !cancelledByCaller,
        });
      }
      throw new ProviderRequestError({
        providerId: this.id,
        code: 'network',
        message: 'Could not reach MangaDex. Check your connection and try again.',
        retryable: true,
      });
    } finally {
      clearTimeout(timeout);
      signal?.removeEventListener('abort', abortFromCaller);
    }
  }

  async search(query: ProviderSearchQuery): Promise<ProviderSearchResult> {
    const text = query.query.trim();
    if (!text) return { listings: [] };
    const params = new URLSearchParams();
    params.set('title', text.slice(0, 160));
    params.set('limit', String(Math.min(50, Math.max(1, query.limit ?? 20))));
    params.set('order[relevance]', 'desc');
    params.append('includes[]', 'cover_art');
    params.append('includes[]', 'author');
    params.append('includes[]', 'artist');
    // A conservative default avoids unexpectedly surfacing explicit titles.
    params.append('contentRating[]', 'safe');
    params.append('contentRating[]', 'suggestive');
    const response = await this.request<ApiResponse<MangaRecord>>(`/manga?${params.toString()}`, query.signal);
    if (!Array.isArray(response.data)) {
      throw new ProviderRequestError({ providerId: this.id, code: 'invalid-response', message: 'MangaDex search data was missing.', retryable: false });
    }
    return { listings: response.data.filter(item => typeof item.id === 'string').map(toListing) };
  }

  async getWorkDetails(providerWorkId: string, signal?: AbortSignal): Promise<ProviderListing> {
    const id = encodeURIComponent(providerWorkId);
    const response = await this.request<{ result?: string; data?: MangaRecord }>(
      `/manga/${id}?includes[]=cover_art&includes[]=author&includes[]=artist`,
      signal,
    );
    if (!response.data || typeof response.data.id !== 'string') {
      throw new ProviderRequestError({ providerId: this.id, code: 'invalid-response', message: 'MangaDex did not return that series.', retryable: false });
    }
    return toListing(response.data);
  }

  async listChapters(providerWorkId: string, signal?: AbortSignal): Promise<ChapterListing[]> {
    const chapters: ChapterListing[] = [];
    for (let page = 0; page < MAX_CHAPTER_PAGES; page++) {
      const params = new URLSearchParams();
      params.set('manga', providerWorkId);
      params.set('limit', String(PAGE_SIZE));
      params.set('offset', String(page * PAGE_SIZE));
      params.set('order[chapter]', 'asc');
      params.set('order[volume]', 'asc');
      params.append('translatedLanguage[]', 'en');
      const response = await this.request<ApiResponse<ChapterRecord>>(`/chapter?${params.toString()}`, signal);
      if (!Array.isArray(response.data)) {
        throw new ProviderRequestError({ providerId: this.id, code: 'invalid-response', message: 'MangaDex chapter data was missing.', retryable: false });
      }
      const mapped = response.data.map(record => {
        const attributes = record.attributes ?? {};
        const chapter = attributes.chapter;
        const numericChapter = chapter && Number.isFinite(Number(chapter)) ? Number(chapter) : undefined;
        return {
          id: `mangadex:chapter:${record.id}`,
          chapterId: `mangadex:chapter:${record.id}`,
          providerId: this.id,
          providerChapterId: record.id,
          url: `https://mangadex.org/chapter/${record.id}`,
          title: attributes.title || undefined,
          numberLabel: chapter || (attributes.title ? 'Oneshot / special' : 'Unnumbered'),
          volumeLabel: attributes.volume || undefined,
          sortOrder: numericChapter,
          kind: chapter ? 'regular' : 'special',
          languageCode: attributes.translatedLanguage,
          pageCount: attributes.pages,
          publishedAt: attributes.publishAt,
          lastVerifiedAt: new Date().toISOString(),
        };
      });
      chapters.push(...mapped);
      const total = typeof response.total === 'number' ? response.total : undefined;
      if (response.data.length < PAGE_SIZE || (total !== undefined && chapters.length >= total)) break;
    }
    return chapters;
  }

  async getChapterPages(providerChapterId: string, signal?: AbortSignal): Promise<string[]> {
    const response = await this.request<AtHomeResponse>(`/at-home/server/${encodeURIComponent(providerChapterId)}`, signal);
    const base = response.baseUrl?.replace(/\\/+$/, '');
    const chapter = response.chapter;
    let safeBase = false;
    try {
      const parsed = new URL(base || '');
      safeBase = parsed.protocol === 'https:' && parsed.hostname === 'uploads.mangadex.org';
    } catch {
      safeBase = false;
    }
    if (!safeBase || !base || !chapter?.hash || !Array.isArray(chapter.data)) {
      throw new ProviderRequestError({ providerId: this.id, code: 'invalid-response', message: 'MangaDex did not provide readable page URLs for this chapter.', retryable: false });
    }
    return chapter.data.map(filename => `${base}/data/${encodeURIComponent(chapter.hash!)}/${encodeURIComponent(filename)}`);
  }

  async healthCheck(signal?: AbortSignal): Promise<ProviderHealth> {
    const checkedAt = new Date().toISOString();
    try {
      await this.request<{ result?: string }>('/ping', signal);
      return { providerId: this.id, state: 'healthy', checkedAt, consecutiveFailures: 0, message: 'MangaDex API responded.' };
    } catch (error) {
      return {
        providerId: this.id,
        state: 'unavailable',
        checkedAt,
        consecutiveFailures: 1,
        message: error instanceof Error ? error.message : 'MangaDex health check failed.',
      };
    }
  }
}

export const mangaDexProvider = new MangaDexProvider();
