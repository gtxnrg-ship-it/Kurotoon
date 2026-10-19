import { useMemo, useState } from 'react';
import {
  ArrowLeft, ArrowUpRight, CheckCircle2, CircleAlert, CloudDownload,
  ExternalLink, FileJson, Globe2, RefreshCw, Search, ShieldAlert, Trash2,
} from 'lucide-react';
import { normalizeRepositoryUrl, parseRepositoryIndex, type IndexedExtension } from '../repositories/registry';

type RepositoryStatus = 'not-checked' | 'healthy' | 'error';
interface RepositoryRecord {
  id: string;
  url: string;
  name: string;
  addedAt: string;
  lastCheckedAt?: string;
  status: RepositoryStatus;
  extensionCount?: number;
  message?: string;
}
const STORAGE_KEY = 'kurotoon.repositories.v1';
const MAX_INDEX_BYTES = 15 * 1024 * 1024;

function loadRepositories(): RepositoryRecord[] {
  if (typeof window === 'undefined') return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((item): item is RepositoryRecord =>
      typeof item === 'object' && item !== null &&
      typeof item.id === 'string' && typeof item.url === 'string' &&
      typeof item.name === 'string' && typeof item.addedAt === 'string' &&
      (item.status === 'not-checked' || item.status === 'healthy' || item.status === 'error'),
    ).slice(0, 50);
  } catch {
    return [];
  }
}

function nameFromUrl(url: string): string {
  try {
    const parsed = new URL(url);
    const segments = parsed.pathname.split('/').filter(Boolean);
    const pathLabel = segments.length > 1 ? segments[segments.length - 2] : '';
    return pathLabel ? parsed.hostname + ' / ' + pathLabel : parsed.hostname;
  } catch {
    return 'Community repository';
  }
}

function readableError(error: unknown): string {
  if (error instanceof Error) {
    if (error.name === 'AbortError') return 'The request timed out or was cancelled.';
    return error.message;
  }
  return 'The repository could not be checked.';
}

function timeLabel(value?: string): string {
  if (!value) return 'Not checked yet';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? 'Last check time unavailable' : date.toLocaleString();
}

export function RepositoryManager({ onBack }: { onBack: () => void }) {
  const [repositories, setRepositories] = useState<RepositoryRecord[]>(loadRepositories);
  const [indexByRepository, setIndexByRepository] = useState<Record<string, IndexedExtension[]>>({});
  const [selectedId, setSelectedId] = useState('');
  const [urlInput, setUrlInput] = useState('');
  const [nameInput, setNameInput] = useState('');
  const [filter, setFilter] = useState('');
  const [notice, setNotice] = useState('');
  const [errorMessage, setErrorMessage] = useState('');
  const [storageWarning, setStorageWarning] = useState('');
  const [saving, setSaving] = useState(false);
  const [refreshingIds, setRefreshingIds] = useState<string[]>([]);

  const selectedRepository = repositories.find((repository) => repository.id === selectedId);
  const visibleExtensions = useMemo(() => {
    const items = selectedId ? indexByRepository[selectedId] || [] : [];
    const needle = filter.trim().toLocaleLowerCase();
    if (!needle) return items;
    return items.filter((item) =>
      [item.name, item.packageName, item.version, item.language, ...item.sources]
        .some((value) => value?.toLocaleLowerCase().includes(needle)),
    );
  }, [filter, indexByRepository, selectedId]);

  function saveRepositoryList(next: RepositoryRecord[]) {
    setRepositories(next);
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
      setStorageWarning('');
    } catch {
      setStorageWarning('This browser could not save repository settings. They will remain available only until this page is closed.');
    }
  }

  function updateRepository(id: string, patch: Partial<RepositoryRecord>) {
    const next = repositories.map((repository) => repository.id === id ? { ...repository, ...patch } : repository);
    saveRepositoryList(next);
  }

  async function refreshRepository(repository: RepositoryRecord) {
    if (refreshingIds.includes(repository.id)) return;
    setRefreshingIds((current) => [...current, repository.id]);
    setNotice('');
    setErrorMessage('');
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), 12000);
    try {
      const response = await fetch(repository.url, {
        signal: controller.signal,
        headers: { Accept: 'application/json' },
        cache: 'no-store',
      });
      if (!response.ok) {
        throw new Error('The server returned HTTP ' + response.status + '. Check the URL or try again later.');
      }
      const lengthHeader = Number(response.headers.get('content-length') || 0);
      if (lengthHeader > MAX_INDEX_BYTES) {
        throw new Error('This index is larger than the 15 MB safety limit for the current web preview.');
      }
      const body = await response.text();
      if (body.length > MAX_INDEX_BYTES) {
        throw new Error('This index is larger than the 15 MB safety limit for the current web preview.');
      }
      let payload: unknown;
      try {
        payload = JSON.parse(body);
      } catch {
        throw new Error('The server did not return valid JSON. Use a direct index.min.json or index.json URL.');
      }
      const parsed = parseRepositoryIndex(payload);
      setIndexByRepository((current) => ({ ...current, [repository.id]: parsed.extensions }));
      updateRepository(repository.id, {
        status: 'healthy',
        extensionCount: parsed.extensions.length,
        lastCheckedAt: new Date().toISOString(),
        message: undefined,
      });
      setSelectedId(repository.id);
      setNotice('Repository checked: ' + parsed.extensions.length + ' extension entr' + (parsed.extensions.length === 1 ? 'y' : 'ies') + ' listed. Only metadata was read.');
    } catch (error) {
      const message = readableError(error);
      setIndexByRepository((current) => {
        const next = { ...current };
        delete next[repository.id];
        return next;
      });
      updateRepository(repository.id, {
        status: 'error',
        lastCheckedAt: new Date().toISOString(),
        message,
      });
      setErrorMessage(repository.name + ': ' + message + ' Some hosts block browser cross-origin requests; that alone does not prove the repository is invalid.');
    } finally {
      window.clearTimeout(timeout);
      setRefreshingIds((current) => current.filter((id) => id !== repository.id));
    }
  }

  async function addRepository(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setErrorMessage('');
    setNotice('');
    let normalizedUrl = '';
    try {
      normalizedUrl = normalizeRepositoryUrl(urlInput);
    } catch (error) {
      setErrorMessage(readableError(error));
      return;
    }
    const existing = repositories.find((repository) => repository.url === normalizedUrl);
    if (existing) {
      setSelectedId(existing.id);
      setErrorMessage('This repository is already in your list. Refresh it instead of adding it again.');
      return;
    }
    if (repositories.length >= 50) {
      setErrorMessage('You have reached the current limit of 50 saved repositories.');
      return;
    }

    const repository: RepositoryRecord = {
      id: 'repo-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 8),
      url: normalizedUrl,
      name: nameInput.trim() || nameFromUrl(normalizedUrl),
      addedAt: new Date().toISOString(),
      status: 'not-checked',
    };
    saveRepositoryList([...repositories, repository]);
    setSelectedId(repository.id);
    setUrlInput('');
    setNameInput('');
    setSaving(true);
    await refreshRepository(repository);
    setSaving(false);
  }

  function removeRepository(repository: RepositoryRecord) {
    const next = repositories.filter((item) => item.id !== repository.id);
    saveRepositoryList(next);
    setIndexByRepository((current) => {
      const cached = { ...current };
      delete cached[repository.id];
      return cached;
    });
    if (selectedId === repository.id) setSelectedId('');
    setNotice('Removed ' + repository.name + ' from this browser.');
    setErrorMessage('');
  }

  return <section className="repository-manager">
    <button className="back-link" onClick={onBack}><ArrowLeft size={16}/> Back to Me settings</button>
    <div className="page-heading">
      <div className="eyebrow">SOURCES & COMMUNITY CATALOGS</div>
      <h1>Repositories.</h1>
      <p>Add repository index URLs, check their metadata, and inspect the source catalogue. Your list is stored locally in this browser.</p>
    </div>

    <div className="repository-callout">
      <div className="repository-callout-icon"><ShieldAlert size={20}/></div>
      <div>
        <strong>Metadata preview — not an extension runtime</strong>
        <p>This web build can read compatible HTTPS JSON indexes. It does not install or execute Android APK extensions, and binary <code>index.pb</code> indexes are not supported yet. An extension catalogue entry does not mean its source is usable in Kurotoon.</p>
      </div>
    </div>

    <form className="repository-add-form" onSubmit={addRepository}>
      <div className="repository-form-heading">
        <div><div className="eyebrow">ADD A REPOSITORY</div><h2>Connect a community index</h2></div>
        <span className="repository-local-pill"><Globe2 size={13}/> HTTPS only</span>
      </div>
      <label className="repository-field">
        <span>Direct index URL</span>
        <input value={urlInput} onChange={(event) => setUrlInput(event.target.value)} placeholder="https://example.org/repo/index.min.json" autoComplete="url" spellCheck={false} required />
      </label>
      <label className="repository-field">
        <span>Display name <small>Optional</small></span>
        <input value={nameInput} onChange={(event) => setNameInput(event.target.value)} placeholder="Name this repository" maxLength={80}/>
      </label>
      <div className="repository-form-foot">
        <p>Paste a direct JSON index URL. A Mihon/Tachiyomi add-repository link is also accepted when it contains a URL parameter.</p>
        <button className="primary repository-add-button" type="submit" disabled={saving || !urlInput.trim()}>{saving ? <RefreshCw size={15} className="spin"/> : <CloudDownload size={16}/>} {saving ? 'Checking index…' : 'Add & check'} </button>
      </div>
    </form>

    {storageWarning && <div className="repository-message warning" role="status"><CircleAlert size={16}/><span>{storageWarning}</span></div>}
    {notice && <div className="repository-message success" role="status"><CheckCircle2 size={16}/><span>{notice}</span></div>}
    {errorMessage && <div className="repository-message error" role="alert"><CircleAlert size={16}/><span>{errorMessage}</span></div>}

    <div className="repository-list-section">
      <div className="section-head">
        <div><div className="eyebrow">YOUR SAVED SOURCES</div><h2>Repository list <span className="repository-count">{repositories.length}</span></h2></div>
        {repositories.length > 0 && <button className="subtle-link" onClick={() => repositories.forEach((repository) => void refreshRepository(repository))}><RefreshCw size={14}/> Refresh all</button>}
      </div>
      {repositories.length === 0 ? <div className="repository-empty">
        <div className="repository-empty-icon"><FileJson size={25}/></div>
        <h3>Your source shelf is empty.</h3>
        <p>Add a trusted repository index to see its listed source metadata. Nothing is installed automatically.</p>
      </div> : <div className="repository-list">
        {repositories.map((repository) => {
          const isRefreshing = refreshingIds.includes(repository.id);
          const selected = selectedId === repository.id;
          return <article className={'repository-card' + (selected ? ' selected' : '')} key={repository.id}>
            <div className="repository-card-top">
              <div className="repository-symbol"><FileJson size={19}/></div>
              <div className="repository-card-copy">
                <h3>{repository.name}</h3>
                <a href={repository.url} target="_blank" rel="noreferrer noopener" className="repository-url">{repository.url}<ExternalLink size={12}/></a>
              </div>
              <span className={'repository-status ' + repository.status}>{repository.status === 'healthy' ? 'Checked' : repository.status === 'error' ? 'Needs attention' : 'Not checked'}</span>
            </div>
            <div className="repository-meta">
              <span>{typeof repository.extensionCount === 'number' ? repository.extensionCount + ' index entr' + (repository.extensionCount === 1 ? 'y' : 'ies') : 'Index not loaded'}</span>
              <span>Last checked: {timeLabel(repository.lastCheckedAt)}</span>
            </div>
            {repository.message && <p className="repository-inline-error"><CircleAlert size={13}/>{repository.message}</p>}
            <div className="repository-actions">
              <button className="subtle-button" onClick={() => void refreshRepository(repository)} disabled={isRefreshing}>{isRefreshing ? <RefreshCw size={14} className="spin"/> : <RefreshCw size={14}/>} Refresh</button>
              <button className="subtle-button" onClick={() => setSelectedId(selected ? '' : repository.id)}>{selected ? 'Hide index' : 'View index'} <ArrowUpRight size={14}/></button>
              <button className="danger-button" onClick={() => removeRepository(repository)}><Trash2 size={14}/> Remove</button>
            </div>
          </article>;
        })}
      </div>}
    </div>

    {selectedRepository && <section className="repository-index-panel">
      <div className="section-head">
        <div><div className="eyebrow">CATALOGUE METADATA</div><h2>{selectedRepository.name}</h2></div>
        <span className="result-source">{selectedRepository.extensionCount ?? 0} entries</span>
      </div>
      {!indexByRepository[selectedRepository.id] ? <div className="repository-index-empty">
        <CircleAlert size={18}/><div><strong>Index details are not loaded in this view.</strong><p>Refresh the repository to retrieve the JSON list. If browser access is blocked by the host, Kurotoon will show that honestly rather than treating it as an empty index.</p></div>
      </div> : <>
        <div className="repository-index-tools">
          <label className="repository-filter"><Search size={16}/><input value={filter} onChange={(event) => setFilter(event.target.value)} placeholder="Filter names, package IDs, language…"/></label>
          <span>{visibleExtensions.length} of {(indexByRepository[selectedRepository.id] || []).length} shown</span>
        </div>
        {visibleExtensions.length === 0 ? <div className="repository-index-empty"><Search size={18}/><div><strong>No matching index entries.</strong><p>Try a shorter filter.</p></div></div> :
          <div className="extension-list">{visibleExtensions.slice(0, 150).map((extension, index) => <ExtensionRow key={(extension.packageName || extension.name) + '-' + index} extension={extension}/>)}</div>}
        {visibleExtensions.length > 150 && <p className="repository-list-limit">Showing the first 150 matches to keep the interface responsive. Narrow your filter to see others.</p>}
      </>}
    </section>}
    <div className="repository-footer-note"><ShieldAlert size={15}/><span>Third-party repositories are not vetted or endorsed by Kurotoon. Only add URLs you trust. The current interface reads metadata; it does not run code from a repository.</span></div>
  </section>;
}

function ExtensionRow({ extension }: { extension: IndexedExtension }) {
  return <article className="extension-row">
    <div className="extension-row-icon"><Globe2 size={16}/></div>
    <div className="extension-row-main">
      <div className="extension-row-title"><strong>{extension.name}</strong>{extension.contentWarning && <span className="content-warning">Content warning</span>}</div>
      <p>{extension.packageName || 'Package ID not supplied'}{extension.version ? ' · v' + extension.version : ''}{extension.language ? ' · ' + extension.language.toUpperCase() : ''}</p>
      {extension.sources.length > 0 && <small>{extension.sources.slice(0, 3).join(' | ')}{extension.sources.length > 3 ? ' +' + (extension.sources.length - 3) + ' more' : ''}</small>}
    </div>
  </article>;
}
