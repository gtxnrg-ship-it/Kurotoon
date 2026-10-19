import { useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowDown, ArrowUp, BookOpen, Bookmark, Check, CircleAlert, Library, RotateCcw, Search, Trash2 } from 'lucide-react';
import type { ProviderListing } from '../domain/models';
import { libraryKey, type LibraryStatus, type SavedSeries } from '../data/repositories';
import { getDataServices } from '../data/services';

type LibraryFilter = 'all' | LibraryStatus;
type LibrarySort = 'manual' | 'recent' | 'title';

const STATUSES: { value: LibraryStatus; label: string }[] = [
  { value: 'reading', label: 'Reading' },
  { value: 'completed', label: 'Completed' },
  { value: 'paused', label: 'Paused' },
  { value: 'planned', label: 'Planned' },
  { value: 'dropped', label: 'Dropped' },
];

export function LibraryScreen({
  active, refreshToken, onOpenSeries, onBrowse,
}: {
  active: boolean;
  refreshToken: number;
  onOpenSeries: (listing: ProviderListing) => void;
  onBrowse: () => void;
}) {
  const [entries, setEntries] = useState<SavedSeries[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [actionError, setActionError] = useState('');
  const [storageMode, setStorageMode] = useState<'indexeddb' | 'memory' | 'unknown'>('unknown');
  const [filter, setFilter] = useState<LibraryFilter>('all');
  const [sort, setSort] = useState<LibrarySort>('manual');
  const [query, setQuery] = useState('');
  const [categoryDrafts, setCategoryDrafts] = useState<Record<string, string>>({});
  const [savingId, setSavingId] = useState('');

  const reload = useCallback(async (alive: () => boolean = () => true) => {
    setLoading(true);
    setLoadError('');
    try {
      const data = await getDataServices();
      const [items] = await Promise.all([data.library.list()]);
      if (!alive()) return;
      setStorageMode(data.store.mode);
      setEntries(items);
      setCategoryDrafts(current => {
        const next = { ...current };
        for (const item of items) {
          if (!(item.id in next)) next[item.id] = item.categoryIds.join(', ');
        }
        return next;
      });
    } catch (error) {
      if (!alive()) return;
      setLoadError(error instanceof Error ? error.message : 'Your library could not be opened.');
    } finally {
      if (alive()) setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!active) return;
    let mounted = true;
    void reload(() => mounted);
    return () => { mounted = false; };
  }, [active, refreshToken, reload]);

  const visibleEntries = useMemo(() => {
    const needle = query.trim().toLocaleLowerCase();
    const filtered = entries.filter(entry => {
      const statusMatches = filter === 'all' || entry.status === filter;
      const categoryText = entry.categoryIds.join(' ');
      const textMatches = !needle || [entry.listing.title, ...entry.listing.aliases, ...entry.listing.creators.map(creator => creator.name), categoryText]
        .some(value => value?.toLocaleLowerCase().includes(needle));
      return statusMatches && textMatches;
    });
    if (sort === 'title') return filtered.sort((a, b) => a.listing.title.localeCompare(b.listing.title));
    if (sort === 'recent') return filtered.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
    return filtered.sort((a, b) => a.sortOrder - b.sortOrder || b.updatedAt.localeCompare(a.updatedAt));
  }, [entries, filter, query, sort]);

  async function updateStatus(entry: SavedSeries, status: LibraryStatus) {
    setSavingId(entry.id);
    setActionError('');
    try {
      const data = await getDataServices();
      await data.library.updateStatus(entry.id, status);
      await reload();
    } catch (error) {
      setActionError(error instanceof Error ? error.message : 'The reading status could not be saved.');
    } finally {
      setSavingId('');
    }
  }

  async function saveCategories(entry: SavedSeries) {
    setSavingId(entry.id);
    setActionError('');
    try {
      const data = await getDataServices();
      const categories = (categoryDrafts[entry.id] ?? '').split(',').map(value => value.trim()).filter(Boolean);
      const saved = await data.library.setCategories(entry.id, categories);
      setEntries(current => current.map(item => item.id === saved.id ? saved : item));
      setCategoryDrafts(current => ({ ...current, [entry.id]: saved.categoryIds.join(', ') }));
    } catch (error) {
      setActionError(error instanceof Error ? error.message : 'The categories could not be saved.');
    } finally {
      setSavingId('');
    }
  }

  async function removeEntry(entry: SavedSeries) {
    setActionError('');
    try {
      const data = await getDataServices();
      await data.library.remove(entry.id);
      setEntries(current => current.filter(item => item.id !== entry.id));
    } catch (error) {
      setActionError(error instanceof Error ? error.message : 'The series could not be removed from your library.');
    }
  }

  async function moveEntry(entry: SavedSeries, direction: -1 | 1) {
    const from = visibleEntries.findIndex(item => item.id === entry.id);
    const target = from + direction;
    if (from < 0 || target < 0 || target >= visibleEntries.length || filter !== 'all' || sort !== 'manual' || query.trim()) return;
    const ids = [...visibleEntries];
    [ids[from], ids[target]] = [ids[target], ids[from]];
    setActionError('');
    try {
      const data = await getDataServices();
      await data.library.reorder(ids.map(item => item.id));
      setEntries(await data.library.list());
    } catch (error) {
      setActionError(error instanceof Error ? error.message : 'The order could not be saved.');
    }
  }

  return <section className="library-screen">
    <header className="page-heading">
      <div className="eyebrow">YOUR PERSONAL COLLECTION</div>
      <h1>Your library.</h1>
      <p>Saved worlds, your reading status, and the path back to each story.</p>
    </header>

    {storageMode === 'memory' && <div className="library-message warning" role="status"><CircleAlert size={16}/><span>Persistent browser storage is unavailable in this session. Changes work for now, but may not survive closing the app.</span></div>}
    {actionError && <div className="library-message error" role="alert"><CircleAlert size={16}/><span>{actionError}</span></div>}
    {loadError && <div className="library-message error" role="alert"><CircleAlert size={16}/><span>{loadError}</span><button onClick={() => void reload()}>Try again</button></div>}

    <div className="library-summary">
      <div><small>SAVED SERIES</small><strong>{entries.length.toLocaleString()}</strong></div>
      <div><small>IN PROGRESS</small><strong>{entries.filter(entry => entry.status === 'reading').length.toLocaleString()}</strong></div>
      <div><small>COMPLETED</small><strong>{entries.filter(entry => entry.status === 'completed').length.toLocaleString()}</strong></div>
    </div>

    <div className="library-tools">
      <label className="library-search"><Search size={17}/><input value={query} onChange={event => setQuery(event.target.value)} placeholder="Search your saved series…" aria-label="Search library"/></label>
      <div className="library-filters">
        <label><span>Status</span><select value={filter} onChange={event => setFilter(event.target.value as LibraryFilter)}><option value="all">All statuses</option>{STATUSES.map(status => <option key={status.value} value={status.value}>{status.label}</option>)}</select></label>
        <label><span>Sort</span><select value={sort} onChange={event => setSort(event.target.value as LibrarySort)}><option value="manual">Manual order</option><option value="recent">Recently updated</option><option value="title">Title A–Z</option></select></label>
      </div>
    </div>

    {loading ? <div className="library-message"><span className="loading-spinner"/><span>Opening your saved collection…</span></div>
      : entries.length === 0 && !loadError ? <div className="library-empty"><div className="library-empty-icon"><Library size={25}/></div><h2>Your collection begins here.</h2><p>Save a series from Browser and it will stay here across app launches when durable storage is available.</p><button className="primary" onClick={onBrowse}>Explore MangaDex <BookOpen size={16}/></button></div>
      : visibleEntries.length === 0 && !loadError ? <div className="library-empty compact"><Search size={20}/><h2>No matching series.</h2><p>Try another title, category, or status.</p><button className="text-link" onClick={() => { setQuery(''); setFilter('all'); }}>Clear filters <RotateCcw size={14}/></button></div>
      : <div className="library-grid">
        {visibleEntries.map((entry, index) => <article className="library-entry" key={entry.id}>
          <button className="library-entry-cover" onClick={() => onOpenSeries(entry.listing)} aria-label={'Open ' + entry.listing.title}>
            {entry.listing.coverUrl ? <img src={entry.listing.coverUrl} alt={entry.listing.title + ' cover'} loading="lazy" decoding="async"/> : <span><BookOpen size={23}/></span>}
          </button>
          <div className="library-entry-body">
            <div className="library-entry-meta"><span className={'library-status status-' + entry.status}>{STATUSES.find(item => item.value === entry.status)?.label ?? entry.status}</span><span>{entry.listing.providerId}</span></div>
            <h2>{entry.listing.title}</h2>
            {entry.listing.creators.length > 0 && <p className="library-entry-creators">{entry.listing.creators.slice(0, 3).map(creator => creator.name).join(' · ')}</p>}
            <button className="library-open-series" onClick={() => onOpenSeries(entry.listing)}><BookOpen size={15}/> Open series</button>
            <div className="library-field-row"><label htmlFor={'library-status-' + entry.id}>Reading status</label><select id={'library-status-' + entry.id} disabled={savingId === entry.id} value={entry.status} onChange={event => void updateStatus(entry, event.target.value as LibraryStatus)}>{STATUSES.map(status => <option key={status.value} value={status.value}>{status.label}</option>)}</select></div>
            <div className="library-field-row category-field"><label htmlFor={'library-categories-' + entry.id}>Categories</label><div><input id={'library-categories-' + entry.id} value={categoryDrafts[entry.id] ?? ''} onChange={event => setCategoryDrafts(current => ({ ...current, [entry.id]: event.target.value }))} placeholder="Favourite, read later…"/><button onClick={() => void saveCategories(entry)} disabled={savingId === entry.id} aria-label="Save categories"><Check size={15}/></button></div></div>
            <footer className="library-entry-footer">
              <span>{entry.lastReadAt ? 'Last read ' + new Date(entry.lastReadAt).toLocaleDateString() : 'Added ' + new Date(entry.addedAt).toLocaleDateString()}</span>
              <div className="library-entry-actions">
                {sort === 'manual' && filter === 'all' && !query.trim() && <><button disabled={index === 0} onClick={() => void moveEntry(entry, -1)} aria-label="Move series up"><ArrowUp size={14}/></button><button disabled={index === visibleEntries.length - 1} onClick={() => void moveEntry(entry, 1)} aria-label="Move series down"><ArrowDown size={14}/></button></>}
                <button className="library-remove" onClick={() => void removeEntry(entry)} aria-label={'Remove ' + entry.listing.title + ' from library'}><Trash2 size={14}/> Remove</button>
              </div>
            </footer>
          </div>
        </article>)}
      </div>}
  </section>;
}
