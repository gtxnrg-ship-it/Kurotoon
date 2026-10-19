import { afterEach, describe, expect, it, vi } from 'vitest';
import { MangaDexProvider } from './mangadex';

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('MangaDexProvider.search', () => {
  it('maps real API fields into the provider listing contract', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({
      result: 'ok',
      data: [{
        id: 'series-123',
        attributes: {
          title: { en: 'The Star Reader', ja: '星の読者' },
          altTitles: [{ en: 'Reader of Stars' }],
          description: { en: 'A story among the stars.' },
          status: 'ongoing',
        },
        relationships: [
          { id: 'cover-1', type: 'cover_art', attributes: { fileName: 'cover.jpg' } },
          { id: 'author-1', type: 'author', attributes: { name: 'A. Creator' } },
          { id: 'artist-1', type: 'artist', attributes: { name: 'B. Artist' } },
        ],
      }],
      total: 1,
    }), { status: 200, headers: { 'Content-Type': 'application/json' } }));
    vi.stubGlobal('fetch', fetchMock);

    const result = await new MangaDexProvider().search({ query: 'Star Reader', limit: 10 });

    expect(result.listings).toHaveLength(1);
    expect(result.listings[0]).toMatchObject({
      providerId: 'mangadex',
      providerWorkId: 'series-123',
      title: 'The Star Reader',
      aliases: expect.arrayContaining(['Reader of Stars', '星の読者']),
      coverUrl: 'https://uploads.mangadex.org/covers/series-123/cover.jpg.256.jpg',
      description: 'A story among the stars.',
      publicationStatus: 'ongoing',
      creators: [
        { id: 'author-1', name: 'A. Creator', role: 'author', providerId: 'mangadex' },
        { id: 'artist-1', name: 'B. Artist', role: 'artist', providerId: 'mangadex' },
      ],
    });
    const requestedUrl = String(fetchMock.mock.calls[0][0]);
    expect(requestedUrl).toContain('/manga?');
    expect(requestedUrl).toContain('contentRating%5B%5D=safe');
  });

  it('does not make a network request for an empty query', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);

    await expect(new MangaDexProvider().search({ query: '   ' })).resolves.toEqual({ listings: [] });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('returns an explicit rate-limit error instead of pretending there are no results', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('rate limited', { status: 429 })));

    await expect(new MangaDexProvider().search({ query: 'Star Reader' })).rejects.toMatchObject({
      providerId: 'mangadex',
      code: 'rate-limited',
      retryable: true,
    });
  });

  it('honours a caller cancellation signal', async () => {
    const controller = new AbortController();
    controller.abort();
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new DOMException('Aborted', 'AbortError')));

    await expect(new MangaDexProvider().search({ query: 'Star Reader', signal: controller.signal })).rejects.toMatchObject({
      providerId: 'mangadex',
      code: 'cancelled',
    });
  });
});
