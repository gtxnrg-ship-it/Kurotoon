import { ArrowUpRight, BookOpen, Bookmark, Check, ExternalLink, Languages } from 'lucide-react';
import type { ProviderListing } from '../domain/models';
import type { UniversalWorkResult } from '../catalog/universalCatalog';
import { libraryKey } from '../data/repositories';
import { formatProviderName, providerRegistry } from '../providers/registry';

function displayLanguage(language?: string): string {
  if (!language) return 'Language not reported';
  try {
    const display = new Intl.DisplayNames(undefined, { type: 'language' }).of(language);
    return display || language;
  } catch {
    return language;
  }
}

function sourceUpdatedAt(listing: ProviderListing): string {
  if (!listing.lastVerifiedAt) return 'Source freshness not checked';
  const date = new Date(listing.lastVerifiedAt);
  return Number.isNaN(date.getTime()) ? 'Source freshness not checked' : 'Verified ' + date.toLocaleDateString();
}

export function UniversalResultCard({
  work,
  savedIds,
  busyIds,
  onOpenSource,
  onToggleSave,
}: {
  work: UniversalWorkResult;
  savedIds: string[];
  busyIds: string[];
  onOpenSource: (listing: ProviderListing) => void;
  onToggleSave: (listing: ProviderListing) => void;
}) {
  const primary = work.listings[0];
  if (!primary) return null;

  const coverListing = work.listings.find(listing => Boolean(listing.coverUrl)) ?? primary;
  const creatorNames = [...new Map(work.listings.flatMap(listing => listing.creators)
    .filter(creator => creator.name.trim())
    .map(creator => [creator.name.trim().toLocaleLowerCase(), creator.name.trim()] as const)).values()];
  const primaryKey = libraryKey(primary);
  const primarySaved = savedIds.includes(primaryKey);
  const primaryBusy = busyIds.includes(primaryKey);
  const languages = work.languageCodes.map(displayLanguage);
  const uniqueSourceCount = work.sourceIds.length;
  const aliases = work.aliases.slice(0, 3);

  return <article className="result-card universal-result-card">
    <div className="result-cover">
      {coverListing.coverUrl
        ? <img src={coverListing.coverUrl} alt={work.canonicalTitle + ' cover'} loading="lazy" decoding="async"/>
        : <div className="cover-fallback"><BookOpen size={23}/></div>}
    </div>
    <div className="result-info universal-result-info">
      <h3>{work.canonicalTitle}</h3>
      {aliases.length > 0 && <p className="universal-aliases">Also known as {aliases.join(' · ')}{work.aliases.length > aliases.length ? ' · +' + (work.aliases.length - aliases.length) + ' more' : ''}</p>}
      {creatorNames.length > 0 && <p className="result-creators">{creatorNames.slice(0, 3).join(' · ')}</p>}
      <div className="universal-result-meta">
        <span className="result-source">{uniqueSourceCount} {uniqueSourceCount === 1 ? 'source' : 'sources'}</span>
        <span>{work.listings.length} {work.listings.length === 1 ? 'listing' : 'listings'}</span>
      </div>
      {languages.length > 0 && <p className="universal-language-meta"><Languages size={13}/>{languages.join(' · ')}</p>}
      <span className={'status-chip ' + primary.publicationStatus}>{primary.publicationStatus === 'unknown' ? 'Status unknown' : primary.publicationStatus}</span>
      {work.latestChapter && <div className="universal-latest">
        <strong>Latest chapter detected: {work.latestChapter.chapterLabel}</strong>
        <small>{formatProviderName(work.latestChapter.providerId)} · {
          work.latestChapterBasis === 'published-at' ? 'publication date' :
          work.latestChapterBasis === 'chapter-number' ? 'chapter number fallback' : 'last verification fallback'
        }{work.latestChapter.publishedAt ? ' · ' + new Date(work.latestChapter.publishedAt).toLocaleDateString() : ''}</small>
        <a href={work.latestChapter.url} target="_blank" rel="noreferrer noopener">Open chapter source <ExternalLink size={12}/></a>
      </div>}
      {primary.description && <p className="result-description">{primary.description}</p>}
      <div className="result-card-actions">
        <button className="result-link" onClick={() => onOpenSource(primary)}>Open in Kurotoon · {formatProviderName(primary.providerId)} <ArrowUpRight size={14}/></button>
        <button className="result-save-button" disabled={primaryBusy} aria-pressed={primarySaved} onClick={() => onToggleSave(primary)}>
          {primarySaved ? <Check size={14}/> : <Bookmark size={14}/>}
          <span>{primaryBusy ? 'Saving…' : primarySaved ? 'Saved' : 'Save'}</span>
        </button>
      </div>
      {work.listings.length > 1 && <details className="universal-source-details">
        <summary>Choose among {work.listings.length} source listings</summary>
        <div className="universal-source-options">
          {work.listings.map(listing => {
            const id = libraryKey(listing);
            const saved = savedIds.includes(id);
            const busy = busyIds.includes(id);
            return <div className="universal-source-option" key={id}>
              <div className="universal-source-copy">
                <strong>{formatProviderName(listing.providerId)}{listing.languageCode ? ' · ' + displayLanguage(listing.languageCode) : ''}</strong>
                {listing.title !== work.canonicalTitle && <span>{listing.title}</span>}
                <small>{sourceUpdatedAt(listing)}</small>
              </div>
              <div className="universal-source-actions">
                <button className="subtle-button" onClick={() => onOpenSource(listing)}>Open</button>
                <button className="subtle-button" disabled={busy} onClick={() => onToggleSave(listing)}>{busy ? 'Saving…' : saved ? 'Saved' : 'Save'}</button>
                <a className="universal-external-link" href={listing.url} target="_blank" rel="noreferrer noopener" aria-label={'Open original listing from ' + formatProviderName(listing.providerId)}><ExternalLink size={14}/></a>
              </div>
            </div>;
          })}
        </div>
      </details>}
    </div>
  </article>;
}
