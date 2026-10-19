import { useCallback, useEffect, useMemo, useRef, useState, type KeyboardEvent, type MouseEvent, type TouchEvent } from 'react';
import {
  ArrowLeft, ArrowLeftRight, BookOpen, Check, ChevronLeft, ChevronRight,
  Home, List, LoaderCircle, MessageCircle, RotateCcw, Settings2, Volume2,
  Vibrate, X, ZoomIn,
} from 'lucide-react';
import type { ChapterListing, ProviderListing } from '../domain/models';
import { isProviderRequestError } from '../domain/provider';
import { mangaDexProvider } from '../providers/mangadex';

type ReaderMode = 'paged' | 'vertical';
type ReaderDirection = 'rtl' | 'ltr';
type ReaderPanel = 'reading' | 'navigation' | 'comments' | 'sound' | 'haptics' | 'more';

const PROGRESS_PREFIX = 'kurotoon:reader-progress:v1';

function progressKey(listing: ProviderListing, chapter: ChapterListing) {
  return PROGRESS_PREFIX + ':' + listing.providerId + ':' + listing.providerWorkId + ':' + chapter.providerChapterId;
}
function readProgress(key: string): { pageIndex: number; scrollRatio: number } {
  try {
    const parsed = JSON.parse(localStorage.getItem(key) || 'null');
    if (parsed && Number.isFinite(parsed.pageIndex)) {
      return {
        pageIndex: Math.max(0, Math.floor(parsed.pageIndex)),
        scrollRatio: Number.isFinite(parsed.scrollRatio) ? Math.min(1, Math.max(0, parsed.scrollRatio)) : 0,
      };
    }
  } catch { /* Storage may be unavailable in private browsing. */ }
  return { pageIndex: 0, scrollRatio: 0 };
}
function readableChapter(chapter: ChapterListing) {
  const number = chapter.numberLabel || 'Unnumbered';
  return chapter.title ? 'Chapter ' + number + ' · ' + chapter.title : 'Chapter ' + number;
}
function friendlyError(error: unknown) {
  if (isProviderRequestError(error)) return error.message;
  return error instanceof Error ? error.message : 'Something went wrong. Please try again.';
}
function formatCount(value: number) {
  return value.toLocaleString();
}

export function SeriesPage({
  listing, onBack, onReadChapter,
}: {
  listing: ProviderListing;
  onBack: () => void;
  onReadChapter: (chapter: ChapterListing, chapters: ChapterListing[]) => void;
}) {
  const [details, setDetails] = useState(listing);
  const [chapters, setChapters] = useState<ChapterListing[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [query, setQuery] = useState('');
  const [ascending, setAscending] = useState(true);
  const onBackRef = useRef(onBack);
  useEffect(() => { onBackRef.current = onBack; }, [onBack]);
  useEffect(() => {
    const currentState = window.history.state;
    if (!(currentState && typeof currentState === 'object' && currentState.__kurotoonSeries)) {
      const stateObject = currentState && typeof currentState === 'object' ? currentState : {};
      window.history.pushState({ ...stateObject, __kurotoonSeries: true }, '', window.location.href);
    }
    const handlePopState = () => onBackRef.current();
    window.addEventListener('popstate', handlePopState);
    return () => window.removeEventListener('popstate', handlePopState);
  }, []);
  const closeSeries = () => {
    if (window.history.state && window.history.state.__kurotoonSeries) window.history.back();
    else onBack();
  };

  useEffect(() => {
    const controller = new AbortController();
    setDetails(listing);
    setChapters([]);
    setLoading(true);
    setError('');
    mangaDexProvider.getWorkDetails(listing.providerWorkId, controller.signal)
      .then(value => { if (!controller.signal.aborted) setDetails(value); })
      .catch(() => { /* Search metadata remains a useful fallback. */ });
    mangaDexProvider.listChapters(listing.providerWorkId, controller.signal)
      .then(value => {
        if (controller.signal.aborted) return;
        const ordered = [...value].sort((a, b) => {
          const left = a.sortOrder ?? Number.POSITIVE_INFINITY;
          const right = b.sortOrder ?? Number.POSITIVE_INFINITY;
          return left - right || (a.numberLabel || '').localeCompare(b.numberLabel || '', undefined, { numeric: true });
        });
        setChapters(ordered);
        setLoading(false);
      })
      .catch(reason => {
        if (controller.signal.aborted || (isProviderRequestError(reason) && reason.code === 'cancelled')) return;
        setError(friendlyError(reason));
        setLoading(false);
      });
    return () => controller.abort();
  }, [listing.providerWorkId]);

  const visibleChapters = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const filtered = chapters.filter(chapter =>
      !needle || [chapter.numberLabel, chapter.title, chapter.volumeLabel].some(value => value?.toLowerCase().includes(needle)),
    );
    return ascending ? filtered : [...filtered].reverse();
  }, [chapters, query, ascending]);

  return <div className="reader-route-overlay series-route" role="main">
    <header className="series-route-bar">
      <button className="reader-icon-button" onClick={closeSeries} aria-label="Back to search results"><ArrowLeft size={19}/></button>
      <span className="series-route-label">SERIES HOME</span>
      <a className="reader-source-link" href={details.url} target="_blank" rel="noreferrer noopener">Source ↗</a>
    </header>
    <div className="series-route-content">
      <section className="series-hero">
        <div className="series-cover">
          {details.coverUrl
            ? <img src={details.coverUrl} alt={details.title + ' cover'} loading="lazy" decoding="async"/>
            : <div className="series-cover-fallback"><BookOpen size={28}/></div>}
        </div>
        <div className="series-intro">
          <div className="reader-eyebrow">MANGADEX · SERIES</div>
          <h1>{details.title}</h1>
          {details.creators.length > 0 && <p className="series-creators">{details.creators.slice(0, 4).map(creator => creator.name).join(' · ')}</p>}
          <div className="series-meta">
            <span>{details.publicationStatus === 'unknown' ? 'Status unknown' : details.publicationStatus}</span>
            <span>{loading ? 'Loading chapters…' : formatCount(chapters.length) + ' chapters found'}</span>
          </div>
          <p className="series-description">{details.description || 'No series description is available from this listing.'}</p>
          <button className="reader-primary-button" onClick={() => {
            if (chapters.length) onReadChapter(chapters[0], chapters);
          }} disabled={loading || chapters.length === 0}>
            <BookOpen size={16}/> {loading ? 'Finding chapters…' : 'Start reading'} <ChevronRight size={16}/>
          </button>
        </div>
      </section>

      <section className="series-chapters">
        <div className="series-chapter-heading">
          <div><div className="reader-eyebrow">YOUR NEXT SCENE</div><h2>Chapters</h2></div>
          <button className="reader-text-button" onClick={() => setAscending(value => !value)} aria-label={ascending ? 'Show newest chapters first' : 'Show oldest chapters first'}>
            <ArrowLeftRight size={15}/>{ascending ? 'Oldest first' : 'Newest first'}
          </button>
        </div>
        <label className="chapter-search"><List size={16}/><input value={query} onChange={event => setQuery(event.target.value)} placeholder="Find a chapter or title…" aria-label="Find a chapter"/></label>
        {loading && <div className="reader-status"><LoaderCircle className="reader-spinner" size={20}/><span>Loading chapter list from MangaDex…</span></div>}
        {!loading && error && <div className="reader-status reader-status-error"><div><strong>Chapters couldn't load.</strong><p>{error}</p><button className="reader-text-button" onClick={() => {
          setLoading(true); setError('');
          mangaDexProvider.listChapters(listing.providerWorkId).then(setChapters).catch(reason => setError(friendlyError(reason))).finally(() => setLoading(false));
        }}><RotateCcw size={14}/> Try again</button></div></div>}
        {!loading && !error && chapters.length === 0 && <div className="reader-status"><span>No English chapters were returned for this series.</span></div>}
        {!loading && !error && chapters.length > 0 && visibleChapters.length === 0 && <div className="reader-status"><span>No chapters match that search.</span></div>}
        <div className="series-chapter-list">
          {visibleChapters.map(chapter => <button key={chapter.providerChapterId} className="series-chapter-row" onClick={() => onReadChapter(chapter, chapters)}>
            <span className="chapter-row-mark"><BookOpen size={16}/></span>
            <span className="chapter-row-copy"><strong>{readableChapter(chapter)}</strong><small>{chapter.volumeLabel ? 'Volume ' + chapter.volumeLabel + ' · ' : ''}{chapter.publishedAt ? new Date(chapter.publishedAt).toLocaleDateString() : 'MangaDex · English listing'}</small></span>
            <ChevronRight size={17}/>
          </button>)}
        </div>
      </section>
      <footer className="reader-route-footer"><span>KUROTOON ✦</span><span>Series home · MangaDex source</span></footer>
    </div>
  </div>;
}

export function ReaderScreen({
  listing, chapters, chapter, onChapterChange, onSeriesHome,
}: {
  listing: ProviderListing;
  chapters: ChapterListing[];
  chapter: ChapterListing;
  onChapterChange: (chapter: ChapterListing) => void;
  onSeriesHome: () => void;
}) {
  const sortedChapters = useMemo(() => [...chapters].sort((a, b) => {
    const left = a.sortOrder ?? Number.POSITIVE_INFINITY;
    const right = b.sortOrder ?? Number.POSITIVE_INFINITY;
    return left - right || (a.numberLabel || '').localeCompare(b.numberLabel || '', undefined, { numeric: true });
  }), [chapters]);
  const chapterIndex = sortedChapters.findIndex(item => item.providerChapterId === chapter.providerChapterId);
  const previousChapter = chapterIndex > 0 ? sortedChapters[chapterIndex - 1] : undefined;
  const nextChapter = chapterIndex >= 0 && chapterIndex < sortedChapters.length - 1 ? sortedChapters[chapterIndex + 1] : undefined;

  const [pages, setPages] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [pageIndex, setPageIndex] = useState(0);
  const [scrollRatio, setScrollRatio] = useState(0);
  const [progressReady, setProgressReady] = useState(false);
  const [mode, setMode] = useState<ReaderMode>('paged');
  const [direction, setDirection] = useState<ReaderDirection>('rtl');
  const [gap, setGap] = useState(0);
  const [autoLoad, setAutoLoad] = useState(true);
  const [visiblePageCount, setVisiblePageCount] = useState(6);
  const [chromeVisible, setChromeVisible] = useState(false);
  const [panel, setPanel] = useState<ReaderPanel | null>(null);
  const [commentsOpen, setCommentsOpen] = useState(false);
  const [failedPages, setFailedPages] = useState<number[]>([]);
  const [retries, setRetries] = useState<Record<number, number>>({});
  const [zoom, setZoom] = useState(100);
  const scrollRef = useRef<HTMLDivElement>(null);
  const sentinelRef = useRef<HTMLDivElement>(null);
  const onExitRef = useRef(onSeriesHome);
  const historyStatePushedRef = useRef(false);
  const touchStartRef = useRef<{ x: number; y: number } | null>(null);
  const lastSwipeAtRef = useRef(0);
  const progressStorageKey = progressKey(listing, chapter);

  useEffect(() => { onExitRef.current = onSeriesHome; }, [onSeriesHome]);

  useEffect(() => {
    const currentState = window.history.state;
    if (!historyStatePushedRef.current) {
      const stateObject = currentState && typeof currentState === 'object' ? currentState : {};
      window.history.pushState({ ...stateObject, __kurotoonReader: true }, '', window.location.href);
      historyStatePushedRef.current = true;
    }
    const handlePopState = () => onExitRef.current();
    window.addEventListener('popstate', handlePopState);
    return () => window.removeEventListener('popstate', handlePopState);
  }, []);

  const loadPages = useCallback(() => {
    const controller = new AbortController();
    setLoading(true);
    setLoadError('');
    setPages([]);
    setFailedPages([]);
    setRetries({});
    setProgressReady(false);
    setVisiblePageCount(6);
    const saved = readProgress(progressStorageKey);
    setPageIndex(saved.pageIndex);
    setScrollRatio(saved.scrollRatio);
    mangaDexProvider.getChapterPages(chapter.providerChapterId, controller.signal)
      .then(urls => {
        if (controller.signal.aborted) return;
        if (!urls.length) throw new Error('This chapter did not return any readable pages.');
        setPages(urls);
        setPageIndex(Math.min(saved.pageIndex, urls.length - 1));
        setLoading(false);
        setProgressReady(true);
      })
      .catch(error => {
        if (controller.signal.aborted) return;
        setLoading(false);
        setLoadError(friendlyError(error));
      });
    return () => controller.abort();
  }, [chapter.providerChapterId, progressStorageKey]);

  useEffect(() => loadPages(), [loadPages]);

  useEffect(() => {
    if (!progressReady || !pages.length) return;
    try {
      localStorage.setItem(progressStorageKey, JSON.stringify({
        pageIndex, scrollRatio,
        updatedAt: new Date().toISOString(),
      }));
    } catch { /* The reader remains usable when storage is full or disabled. */ }
  }, [pageIndex, scrollRatio, progressReady, pages.length, progressStorageKey]);

  useEffect(() => {
    if (mode !== 'vertical' || !autoLoad || !sentinelRef.current || !scrollRef.current || visiblePageCount >= pages.length) return;
    const root = scrollRef.current;
    const sentinel = sentinelRef.current;
    if (typeof IntersectionObserver === 'undefined') {
      setVisiblePageCount(count => Math.min(pages.length, count + 4));
      return;
    }
    const observer = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) setVisiblePageCount(count => Math.min(pages.length, count + 4));
    }, { root, rootMargin: '1000px 0px' });
    observer.observe(sentinel);
    return () => observer.disconnect();
  }, [mode, autoLoad, visiblePageCount, pages.length, chapter.providerChapterId]);

  useEffect(() => {
    if (mode !== 'vertical' || !progressReady || !scrollRef.current || scrollRatio <= 0) return;
    const root = scrollRef.current;
    const raf = window.requestAnimationFrame(() => {
      const available = Math.max(0, root.scrollHeight - root.clientHeight);
      root.scrollTop = available * scrollRatio;
    });
    return () => window.cancelAnimationFrame(raf);
  }, [mode, progressReady, pages.length]);

  useEffect(() => {
    if (!pages.length || loading || mode !== 'paged') return;
    // Keep decoding bounded: current page plus its immediate neighbours only.
    [pageIndex - 1, pageIndex, pageIndex + 1].filter(index => index >= 0 && index < pages.length).forEach(index => {
      const image = new Image();
      image.decoding = 'async';
      image.src = pages[index];
    });
  }, [pageIndex, pages, loading, mode]);

  const changeChapter = useCallback((target?: ChapterListing) => {
    if (!target) return;
    setPanel(null);
    setCommentsOpen(false);
    setChromeVisible(false);
    onChapterChange(target);
  }, [onChapterChange]);

  const turnPage = useCallback((delta: number) => {
    if (!pages.length) return;
    setPageIndex(current => Math.min(pages.length - 1, Math.max(0, current + delta)));
  }, [pages.length]);

  const goNext = useCallback(() => {
    if (pageIndex < pages.length - 1) turnPage(1);
    else if (nextChapter) changeChapter(nextChapter);
  }, [pageIndex, pages.length, nextChapter, turnPage, changeChapter]);

  const handleStageClick = (event: MouseEvent<HTMLDivElement>) => {
    if (performance.now() - lastSwipeAtRef.current < 450) return;
    if (panel || commentsOpen) return;
    const target = event.target as HTMLElement;
    if (target.closest('button, a, input, select, textarea')) return;
    if (mode === 'vertical') {
      setChromeVisible(value => !value);
      return;
    }
    const bounds = event.currentTarget.getBoundingClientRect();
    const fraction = (event.clientX - bounds.left) / Math.max(1, bounds.width);
    if (fraction < 0.23) {
      turnPage(direction === 'rtl' ? 1 : -1);
    } else if (fraction > 0.77) {
      turnPage(direction === 'rtl' ? -1 : 1);
    } else {
      setChromeVisible(value => !value);
    }
  };

  const handleTouchStart = (event: TouchEvent<HTMLDivElement>) => {
    const touch = event.changedTouches[0];
    touchStartRef.current = { x: touch.clientX, y: touch.clientY };
  };
  const handleTouchEnd = (event: React.TouchEvent<HTMLDivElement>) => {
    const start = touchStartRef.current;
    touchStartRef.current = null;
    if (!start || mode !== 'paged' || panel || commentsOpen) return;
    const touch = event.changedTouches[0];
    const dx = touch.clientX - start.x;
    const dy = touch.clientY - start.y;
    const width = window.innerWidth;
    // Leave the outermost edge zones to Android/iOS system-back gestures.
    if (start.x < 24 || start.x > width - 24) return;
    if (Math.abs(dx) < 62 || Math.abs(dx) < Math.abs(dy) * 1.25) return;
    lastSwipeAtRef.current = performance.now();
    const forward = direction === 'rtl' ? dx > 0 : dx < 0;
    turnPage(forward ? 1 : -1);
  };

  const handleReaderKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.key === 'Escape') {
      if (commentsOpen) setCommentsOpen(false);
      else if (panel) setPanel(null);
      else if (chromeVisible) setChromeVisible(false);
      else window.history.back();
      return;
    }
    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
      if (mode !== 'paged' || panel || commentsOpen) return;
      const right = event.key === 'ArrowRight';
      const forward = direction === 'rtl' ? !right : right;
      turnPage(forward ? 1 : -1);
    }
  };

  const openPanel = (next: ReaderPanel) => {
    setCommentsOpen(false);
    setPanel(next);
    setChromeVisible(true);
  };
  const closeReader = () => {
    if (window.history.state && window.history.state.__kurotoonReader) window.history.back();
    else onSeriesHome();
  };
  const rememberVerticalPosition = () => {
    const root = scrollRef.current;
    if (!root) return;
    const available = Math.max(1, root.scrollHeight - root.clientHeight);
    setScrollRatio(Math.max(0, Math.min(1, root.scrollTop / available)));
    const images = Array.from(root.querySelectorAll<HTMLImageElement>('img[data-page-index]'));
    const reference = root.getBoundingClientRect().top + root.clientHeight * 0.45;
    let visibleIndex = 0;
    for (const image of images) {
      if (image.getBoundingClientRect().top <= reference) visibleIndex = Number(image.dataset.pageIndex || 0);
      else break;
    }
    setPageIndex(visibleIndex);
  };

  const currentLabel = chapter.numberLabel ? 'Chapter ' + chapter.numberLabel : 'Chapter';
  const pageFailed = (index: number) => failedPages.includes(index);
  const markFailed = (index: number) => setFailedPages(current => current.includes(index) ? current : [...current, index]);
  const retryPage = (index: number) => {
    setFailedPages(current => current.filter(value => value !== index));
    setRetries(current => ({ ...current, [index]: (current[index] || 0) + 1 }));
  };

  return <div className="reader-route-overlay reader-screen" role="main" tabIndex={-1} onKeyDown={handleReaderKeyDown}>
    <div className="reader-top-chrome">
      <button className="reader-home-button" onClick={closeReader} aria-label="Return to this series home"><Home size={18}/><span>Series home</span></button>
      {chromeVisible && <div className="reader-top-title"><strong>{currentLabel}</strong><small>{listing.title}</small></div>}
      {chromeVisible && <button className="reader-icon-button reader-chapter-list-shortcut" onClick={() => openPanel('navigation')} aria-label="Open chapter navigation"><List size={18}/></button>}
    </div>

    <div className={'reader-stage ' + (mode === 'vertical' ? 'reader-stage-vertical' : 'reader-stage-paged')}
      ref={scrollRef}
      onClick={handleStageClick}
      onTouchStart={handleTouchStart}
      onTouchEnd={handleTouchEnd}
      onScroll={mode === 'vertical' ? rememberVerticalPosition : undefined}
      style={mode === 'vertical' ? { gap: gap + 'px' } : undefined}
      aria-label={listing.title + ', ' + currentLabel}>
      {loading && <div className="reader-loading"><LoaderCircle className="reader-spinner" size={27}/><strong>Opening your chapter…</strong><span>Fetching page images from MangaDex.</span></div>}
      {!loading && loadError && <div className="reader-error-state"><div className="reader-error-icon"><BookOpen size={24}/></div><h2>We couldn't open this chapter.</h2><p>{loadError}</p><button className="reader-primary-button" onClick={loadPages}><RotateCcw size={15}/> Retry chapter</button><button className="reader-text-button" onClick={closeReader}><ArrowLeft size={14}/> Back to series</button></div>}
      {!loading && !loadError && pages.length > 0 && mode === 'paged' && <>
        <div className="reader-paged-image-wrap">
          {pageFailed(pageIndex)
            ? <div className="reader-page-failed"><strong>Page {pageIndex + 1} couldn't load.</strong><button className="reader-primary-button" onClick={event => { event.stopPropagation(); retryPage(pageIndex); }}><RotateCcw size={14}/> Retry page</button></div>
            : <img key={pages[pageIndex] + ':' + (retries[pageIndex] || 0)} className="reader-page-image" src={pages[pageIndex]} alt={'Page ' + (pageIndex + 1) + ' of ' + pages.length} draggable={false} decoding="async" onError={() => markFailed(pageIndex)} style={{ maxHeight: 'calc(100svh - 104px)', transform: 'scale(' + zoom / 100 + ')' }}/>}
        </div>
        <div className={'reader-page-status ' + (chromeVisible ? 'reader-page-status-visible' : '')}>
          <span>{pageIndex + 1} / {pages.length}</span><span>{direction === 'rtl' ? 'Right to left' : 'Left to right'}</span>
        </div>
        {pageIndex === pages.length - 1 && <ChapterEndActions listing={listing} chapter={chapter} previousChapter={previousChapter} nextChapter={nextChapter} onPrevious={() => changeChapter(previousChapter)} onNext={() => changeChapter(nextChapter)} onSeriesHome={closeReader} onComments={() => { setPanel(null); setCommentsOpen(true); }} currentPage={pageIndex + 1} />}
      </>}
      {!loading && !loadError && pages.length > 0 && mode === 'vertical' && <>
        <div className="reader-vertical-pages">
          {pages.slice(0, visiblePageCount).map((url, index) => <div className="reader-vertical-page" key={url + ':' + (retries[index] || 0)} style={{ marginBottom: gap + 'px' }}>
            {pageFailed(index)
              ? <div className="reader-page-failed"><strong>Page {index + 1} couldn't load.</strong><button className="reader-primary-button" onClick={() => retryPage(index)}><RotateCcw size={14}/> Retry page</button></div>
              : <img data-page-index={index} src={url} alt={'Page ' + (index + 1)} loading={index < 3 ? 'eager' : 'lazy'} decoding="async" draggable={false} onError={() => markFailed(index)} />}
          </div>)}
        </div>
        {visiblePageCount < pages.length && <div ref={sentinelRef} className="reader-load-sentinel">
          {autoLoad ? <><LoaderCircle className="reader-spinner" size={17}/> Loading the next pages…</> : <button className="reader-primary-button" onClick={() => setVisiblePageCount(count => Math.min(pages.length, count + 4))}>Load more pages <ChevronRight size={15}/></button>}
        </div>}
        {visiblePageCount >= pages.length && <ChapterEndActions listing={listing} chapter={chapter} previousChapter={previousChapter} nextChapter={nextChapter} onPrevious={() => changeChapter(previousChapter)} onNext={() => changeChapter(nextChapter)} onSeriesHome={closeReader} onComments={() => { setPanel(null); setCommentsOpen(true); }} currentPage={pageIndex + 1} />}
      </>}
    </div>

    {chromeVisible && !panel && !commentsOpen && <div className="reader-bottom-chrome" aria-label="Reader navigation">
      <button onClick={() => changeChapter(previousChapter)} disabled={!previousChapter}><ChevronLeft size={17}/><span>Previous</span></button>
      <button onClick={() => openPanel('navigation')}><List size={17}/><span>Chapters</span></button>
      <button onClick={() => openPanel('comments')}><MessageCircle size={17}/><span>Comments</span></button>
      <button onClick={() => changeChapter(nextChapter)} disabled={!nextChapter}><span>Next</span><ChevronRight size={17}/></button>
    </div>}

    <button className="reader-gear-button" onClick={() => {
      if (panel) { setPanel(null); setChromeVisible(false); }
      else { setCommentsOpen(false); setPanel('reading'); setChromeVisible(true); }
    }} aria-label={panel ? 'Close reader settings' : 'Open reader settings'} aria-expanded={Boolean(panel)}>
      {panel ? <X size={20}/> : <Settings2 size={20}/>}
    </button>

    {panel && <div className="reader-sheet-backdrop" onClick={() => setPanel(null)}>
      <section className="reader-settings-sheet" onClick={event => event.stopPropagation()} aria-label="Reader settings" role="dialog" aria-modal="true">
        <div className="reader-sheet-handle"/>
        <header className="reader-sheet-heading"><div><div className="reader-eyebrow">KUROTOON READER</div><h2>{panel === 'reading' ? 'Reading' : panel === 'navigation' ? 'Navigation' : panel === 'comments' ? 'Comments' : panel === 'sound' ? 'Sound & voice' : panel === 'haptics' ? 'Haptics' : 'More options'}</h2></div><button className="reader-icon-button" onClick={() => setPanel(null)} aria-label="Close settings"><X size={19}/></button></header>
        <nav className="reader-sheet-tabs" aria-label="Reader setting sections">
          <button className={panel === 'reading' ? 'active' : ''} onClick={() => setPanel('reading')}><BookOpen size={15}/><span>Reading</span></button>
          <button className={panel === 'navigation' ? 'active' : ''} onClick={() => setPanel('navigation')}><ArrowLeftRight size={15}/><span>Navigate</span></button>
          <button className={panel === 'comments' ? 'active' : ''} onClick={() => setPanel('comments')}><MessageCircle size={15}/><span>Comments</span></button>
          <button className={panel === 'sound' ? 'active' : ''} onClick={() => setPanel('sound')}><Volume2 size={15}/><span>Audio</span></button>
          <button className={panel === 'haptics' ? 'active' : ''} onClick={() => setPanel('haptics')}><Vibrate size={15}/><span>Haptics</span></button>
        </nav>
        <div className="reader-sheet-content">
          {panel === 'reading' && <>
            <div className="reader-control-group"><div className="reader-control-label">Reading layout</div><div className="reader-segment">
              <button className={mode === 'paged' ? 'selected' : ''} onClick={() => { setMode('paged'); setChromeVisible(false); }}>Paged</button>
              <button className={mode === 'vertical' ? 'selected' : ''} onClick={() => { setMode('vertical'); setChromeVisible(false); }}>Vertical</button>
            </div></div>
            {mode === 'paged' && <div className="reader-control-group"><div className="reader-control-label">Reading direction</div><div className="reader-segment">
              <button className={direction === 'ltr' ? 'selected' : ''} onClick={() => setDirection('ltr')}>Left to right</button>
              <button className={direction === 'rtl' ? 'selected' : ''} onClick={() => setDirection('rtl')}>Right to left</button>
            </div><p className="reader-control-help">This changes page turns and swipe direction, not the original artwork.</p></div>}
            {mode === 'vertical' && <><div className="reader-control-group"><div className="reader-control-label">Space between pages <strong>{gap}px</strong></div><input className="reader-range" type="range" min="0" max="32" step="2" value={gap} onChange={event => setGap(Number(event.target.value))}/></div><div className="reader-setting-toggle"><span><strong>Load pages automatically</strong><small>Bring in a few pages at a time as you read.</small></span><button className={'reader-toggle ' + (autoLoad ? 'on' : '')} onClick={() => setAutoLoad(value => !value)} role="switch" aria-checked={autoLoad}><i/></button></div></>}
            {mode === 'paged' && <div className="reader-control-group"><div className="reader-control-label">Page zoom <strong>{zoom}%</strong></div><input className="reader-range" type="range" min="70" max="130" step="5" value={zoom} onChange={event => setZoom(Number(event.target.value))}/><p className="reader-control-help"><ZoomIn size={13}/> Zoom applies to the current page view.</p></div>}
            <div className="reader-control-group"><div className="reader-control-label">Page position</div><div className="reader-inline-action"><span>{pages.length ? 'Page ' + (pageIndex + 1) + ' of ' + pages.length : 'Page position will appear when loaded'}</span><button className="reader-text-button" onClick={() => { setPageIndex(0); setScrollRatio(0); if (scrollRef.current) scrollRef.current.scrollTop = 0; setPanel(null); }}>Return to start</button></div></div>
          </>}
          {panel === 'navigation' && <>
            <div className="reader-control-group"><div className="reader-control-label">Current chapter</div><div className="reader-current-chapter"><strong>{readableChapter(chapter)}</strong><small>{listing.title}</small></div></div>
            <div className="reader-chapter-nav-buttons"><button onClick={() => changeChapter(previousChapter)} disabled={!previousChapter}><ChevronLeft size={17}/><span><small>Previous</small><strong>{previousChapter ? readableChapter(previousChapter) : 'Beginning of list'}</strong></span></button><button onClick={() => changeChapter(nextChapter)} disabled={!nextChapter}><ChevronRight size={17}/><span><small>Next</small><strong>{nextChapter ? readableChapter(nextChapter) : 'End of list'}</strong></span></button></div>
            <div className="reader-control-group"><div className="reader-control-label">Return to</div><button className="reader-full-width-action" onClick={closeReader}><Home size={17}/><span><strong>Series home</strong><small>Return to this series’ details and chapter list.</small></span><ChevronRight size={16}/></button></div>
            <p className="reader-control-help">Edge swipes are left to the phone's system navigation. Swipe across the page area or use the buttons above to change chapters.</p>
          </>}
          {panel === 'comments' && <div className="reader-comments-info"><div className="reader-comments-icon"><MessageCircle size={22}/></div><h3>Discuss this moment</h3><p>You're on {readableChapter(chapter)}, page {pageIndex + 1}. Kurotoon will keep this reading position when you open or close a discussion.</p><div className="reader-spoiler-note"><Check size={15}/><span>Future comments will support chapter-aware spoiler warnings and moment anchors.</span></div><div className="reader-coming-soon"><strong>Discussion service not connected yet</strong><span>This build doesn't fetch or publish comments. The panel is a clearly marked placeholder until a real community backend is available.</span></div><button className="reader-primary-button" onClick={() => setPanel('navigation')}>Back to navigation <ChevronRight size={15}/></button></div>}
          {panel === 'sound' && <PlannedPanel icon="audio" title="Sound & voice" description="Independent music, ambience, effects, dialogue, narration, and voice controls will arrive with the shared reader timeline. They are not enabled in this build."/>}
          {panel === 'haptics' && <PlannedPanel icon="haptics" title="Haptics" description="Optional event-based vibration and intensity settings are planned. Nothing vibrates automatically in this build."/>}
          {panel === 'more' && <PlannedPanel icon="more" title="More options" description="Accessibility and advanced reader preferences will be added here as they become functional."/>}
        </div>
      </section>
    </div>}

    {commentsOpen && <div className="reader-sheet-backdrop" onClick={() => setCommentsOpen(false)}>
      <section className="reader-settings-sheet reader-comments-sheet" onClick={event => event.stopPropagation()} role="dialog" aria-modal="true" aria-label="Comments for this moment">
        <div className="reader-sheet-handle"/><header className="reader-sheet-heading"><div><div className="reader-eyebrow">CURRENT READING POSITION</div><h2>Comments & reactions</h2></div><button className="reader-icon-button" onClick={() => setCommentsOpen(false)} aria-label="Close comments"><X size={19}/></button></header>
        <div className="reader-comments-info"><div className="reader-comments-icon"><MessageCircle size={22}/></div><h3>{readableChapter(chapter)} · page {pageIndex + 1}</h3><p>Moment-specific discussion belongs here, without sending you away from the artwork.</p><div className="reader-coming-soon"><strong>Comments aren't live yet</strong><span>There is no comment backend connected, so Kurotoon won't invent reactions or pretend that comments have been posted.</span></div><button className="reader-full-width-action" onClick={() => { setCommentsOpen(false); setPanel('comments'); setChromeVisible(true); }}><MessageCircle size={17}/><span><strong>Discussion & spoiler design</strong><small>Review how moment anchors and chapter-aware spoilers will work.</small></span><ChevronRight size={16}/></button></div>
      </section>
    </div>}
  </div>;
}

function ChapterEndActions({
  listing, chapter, previousChapter, nextChapter, onPrevious, onNext, onSeriesHome, onComments, currentPage,
}: {
  listing: ProviderListing;
  chapter: ChapterListing;
  previousChapter?: ChapterListing;
  nextChapter?: ChapterListing;
  onPrevious: () => void;
  onNext: () => void;
  onSeriesHome: () => void;
  onComments: () => void;
  currentPage: number;
}) {
  return <section className="reader-chapter-end" aria-label="Chapter end navigation">
    <div className="reader-eyebrow">END OF CHAPTER</div>
    <h2>Where to next?</h2><p>{listing.title} · {readableChapter(chapter)}</p>
    <div className="reader-end-actions">
      <button onClick={onSeriesHome}><Home size={17}/><span>Series home</span></button>
      <button disabled={!previousChapter} onClick={onPrevious}><ChevronLeft size={17}/><span>Previous</span></button>
      <button disabled={!nextChapter} className="reader-end-next" onClick={onNext}><span>Next chapter</span><ChevronRight size={17}/></button>
    </div>
    <button className="reader-end-comments" onClick={onComments}><MessageCircle size={15}/> Comments for this moment <span>·</span> page {currentPage}</button>
  </section>;
}

function PlannedPanel({ icon, title, description }: { icon: 'audio' | 'haptics' | 'more'; title: string; description: string }) {
  const Icon = icon === 'audio' ? Volume2 : icon === 'haptics' ? Vibrate : Settings2;
  return <div className="reader-planned-panel"><div className="reader-planned-icon"><Icon size={22}/></div><span className="reader-planned-badge">PLANNED</span><h3>{title}</h3><p>{description}</p></div>;
}
