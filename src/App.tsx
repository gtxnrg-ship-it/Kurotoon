import { useEffect, useState } from 'react';
import { AudioLines, ArrowRight, ArrowUpRight, BookOpen, Bookmark, ChevronRight, Compass, Headphones, Library, Search, Settings2, ShieldCheck, Sparkles, Store, WandSparkles, Wifi, Download, CircleHelp } from 'lucide-react';
import { CosmicBackdrop } from './components/CosmicBackdrop';
import type { ProviderListing } from './domain/models';
import { isProviderRequestError } from './domain/provider';
import { mangaDexProvider } from './providers/mangadex';

type Destination = 'Home' | 'Browser' | 'Shop' | 'Library' | 'Me';
const nav: { name: Destination; icon: typeof Compass }[] = [
  { name: 'Home', icon: Sparkles }, { name: 'Browser', icon: Compass }, { name: 'Shop', icon: Store }, { name: 'Library', icon: Library }, { name: 'Me', icon: Settings2 },
];

function Heading({ eyebrow, title, description }: { eyebrow: string; title: string; description: string }) {
  return <div className="page-heading"><div className="eyebrow">{eyebrow}</div><h1>{title}</h1><p>{description}</p></div>;
}
function EmptyState({ icon: Icon, title, text, action, onAction }: { icon: typeof BookOpen; title: string; text: string; action?: string; onAction?: () => void }) {
  return <div className="empty-state"><div className="empty-icon"><Icon size={23}/></div><h3>{title}</h3><p>{text}</p>{action && onAction && <button className="text-link" onClick={onAction}>{action}<ArrowRight size={15}/></button>}</div>;
}
function App() {
  const [active, setActive] = useState<Destination>('Home');
  const [query, setQuery] = useState('');
  const [searchKey, setSearchKey] = useState(0);
  const [results, setResults] = useState<ProviderListing[]>([]);
  const [searchStatus, setSearchStatus] = useState<'idle' | 'loading' | 'success' | 'empty' | 'error'>('idle');
  const [searchError, setSearchError] = useState('');
  useEffect(() => {
    const trimmed = query.trim();
    if (!trimmed) {
      setResults([]);
      setSearchError('');
      setSearchStatus('idle');
      return;
    }
    const controller = new AbortController();
    setSearchStatus('loading');
    setSearchError('');
    const timer = window.setTimeout(() => {
      void mangaDexProvider.search({ query: trimmed, limit: 20, signal: controller.signal })
        .then(response => {
          if (controller.signal.aborted) return;
          setResults(response.listings);
          setSearchStatus(response.listings.length ? 'success' : 'empty');
        })
        .catch(error => {
          if (controller.signal.aborted || (isProviderRequestError(error) && error.code === 'cancelled')) return;
          setResults([]);
          setSearchStatus('error');
          setSearchError(error instanceof Error ? error.message : 'Something went wrong while searching MangaDex.');
        });
    }, 350);
    return () => {
      window.clearTimeout(timer);
      controller.abort();
    };
  }, [query, searchKey]);
  const Settings = [
    { icon: BookOpen, title: 'Reading experience', detail: 'Layout, gestures, progress, and accessibility' },
    { icon: AudioLines, title: 'Sound & voice', detail: 'Future audio modes and independent volume controls' },
    { icon: Download, title: 'Storage & offline', detail: 'Cache limits, cleanup, and download preferences' },
    { icon: Wifi, title: 'Repositories & sources', detail: 'Repository URLs, extensions, and provider health' },
    { icon: ShieldCheck, title: 'Privacy & data', detail: 'Local data, backup, and external processing controls' },
    { icon: CircleHelp, title: 'About & diagnostics', detail: 'Build status, known limits, and troubleshooting' },
  ];
  return <div className="app-shell">
    <CosmicBackdrop />
    <header className="topbar">
      <button className="brand" onClick={() => setActive('Home')} aria-label="Kurotoon home"><span className="brand-mark"><i/><i/><i/></span><span>kuro<span className="brand-accent">toon</span></span></button>
      <div className="top-actions"><span className="live-pill"><i/> Living cosmos preview</span><button className="avatar" onClick={() => setActive('Me')} aria-label="Open settings">K</button></div>
    </header>
    <aside className="sidebar"><div className="side-label">YOUR SPACE</div><nav>{nav.map(({name,icon:Icon})=><button key={name} onClick={()=>setActive(name)} className={'nav-item '+(active===name?'active':'')} aria-current={active===name?'page':undefined}><Icon size={19}/><span>{name}</span>{name==='Shop'&&<small>SOON</small>}</button>)}</nav><div className="side-bottom"><span className="side-star"><Sparkles size={16}/></span><p>A universe of stories.<br/><small>One home for all of them.</small></p><div className="build-tag"><i/> FOUNDATION BUILD</div></div></aside>
    <main className="main-content"><div className="mobile-label">KUROTOON <span>/</span> {active.toUpperCase()}</div><div className="content">
      {active==='Home'&&<>
        <section className="hero"><div className="hero-copy"><div className="hero-kicker"><Sparkles size={14}/> YOUR NEXT CHAPTER STARTS HERE</div><h1>Read beyond<br/>the <span>page.</span></h1><p>All your worlds, all your stories — one beautifully connected universe.</p><button className="primary" onClick={()=>setActive('Browser')}>Explore the universe <ArrowRight size={16}/></button><div className="hero-foot"><span>✦</span> Built around the way you love to read</div></div><div className="cosmos" aria-hidden="true"><div className="ring ring-a"/><div className="ring ring-b"/><div className="planet"><i/><i/><i/></div><b className="star star-a">✦</b><b className="star star-b">✧</b><span className="float float-a"><AudioLines size={14}/> Immersive reading</span><span className="float float-b"><Bookmark size={14}/> Your library</span></div><div className="hero-index">01 <span>/ THE BEGINNING</span></div></section>
        <section className="section"><div className="section-head"><div><div className="eyebrow">PICK UP WHERE YOU LEFT OFF</div><h2>Your story continues.</h2></div><button className="subtle-link" onClick={()=>setActive('Library')}>Open library <ArrowRight size={14}/></button></div><div className="continue-card"><div className="continue-icon"><BookOpen size={23}/></div><div><h3>Your next read is waiting</h3><p>When your library is connected, your in-progress stories will find their place here.</p></div><button className="round-link" onClick={()=>setActive('Library')} aria-label="Open library"><ArrowUpRight size={18}/></button></div></section>
        <section className="section"><div className="section-head"><div><div className="eyebrow">WIDE OPEN WORLDS</div><h2>Find your next obsession.</h2></div><button className="subtle-link" onClick={()=>setActive('Browser')}>Browse stories <ArrowRight size={14}/></button></div><div className="feature-grid"><button className="feature purple" onClick={()=>setActive('Browser')}><Compass size={19}/><small>01 / DISCOVER</small><h3>One search.<br/>Many worlds.</h3><p>A unified doorway to your comic sources.</p><ArrowRight className="feature-arrow" size={17}/></button><button className="feature blue" onClick={()=>setActive('Library')}><Library size={19}/><small>02 / COLLECT</small><h3>Your worlds,<br/>in one place.</h3><p>A library that remembers your progress.</p><ArrowRight className="feature-arrow" size={17}/></button><button className="feature pink" onClick={()=>setActive('Me')}><Headphones size={19}/><small>03 / EXPERIENCE</small><h3>More than<br/>just pages.</h3><p>Optional sound and cinematic reading.</p><ArrowRight className="feature-arrow" size={17}/></button></div></section>
        <div className="notice"><ShieldCheck size={16}/><span>This is the first interface foundation. Live providers, account sync, and reader features will be added and verified in later milestones.</span></div>
      </>}
      {active==='Browser'&&<><Heading eyebrow="THE MULTIVERSE IS YOURS" title="Find your next world." description="Search live MangaDex listings. More providers can join this catalog as they are implemented."/><form className="search-box" onSubmit={event=>{event.preventDefault();setSearchKey(value=>value+1)}}><Search size={20}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search titles or alternate names…" aria-label="Search comics"/><button type="submit" aria-label="Search" disabled={!query.trim()}><ArrowRight size={18}/></button></form><div className="source-caption"><span className="source-dot"/> MangaDex · live source <span>·</span> English chapters are used when listing chapters</div>{searchStatus==='loading'&&<div className="status-panel" role="status"><span className="loading-spinner"/><div><strong>Searching the universe…</strong><p>Fetching real results from MangaDex.</p></div></div>}{searchStatus==='error'&&<div className="status-panel status-error" role="alert"><i/><div><strong>Search couldn't complete</strong><p>{searchError}</p><button className="text-link" onClick={()=>setSearchKey(value=>value+1)}>Try again <ArrowRight size={15}/></button></div></div>}{searchStatus==='empty'&&<div className="section"><EmptyState icon={Search} title="No matching titles found" text="MangaDex returned no matches for this query. Try an alternate title or fewer words."/></div>}{searchStatus==='idle'&&<div className="section"><EmptyState icon={Compass} title="Your next world is waiting" text="Search for a title to fetch real listings. Results are never filled with pretend demo series."/></div>}{searchStatus==='success'&&<section className="section"><div className="section-head"><div><div className="eyebrow">LIVE PROVIDER RESULTS</div><h2>{results.length} {results.length===1?'series':'series'} found</h2></div><span className="result-source">MangaDex</span></div><div className="results-grid">{results.map(item=><article className="result-card" key={item.providerWorkId}><div className="result-cover">{item.coverUrl?<img src={item.coverUrl} alt={item.title+' cover'} loading="lazy" decoding="async"/>:<div className="cover-fallback"><BookOpen size={23}/></div>}</div><div className="result-info"><h3>{item.title}</h3>{item.creators.length>0&&<p className="result-creators">{item.creators.slice(0,2).map(creator=>creator.name).join(' · ')}</p>}<span className={'status-chip '+item.publicationStatus}>{item.publicationStatus==='unknown'?'Status unknown':item.publicationStatus}</span>{item.description&&<p className="result-description">{item.description}</p>}<a className="result-link" href={item.url} target="_blank" rel="noreferrer noopener">Open on MangaDex <ArrowUpRight size={14}/></a></div></article>)}</div><p className="results-footnote">Listings and cover art are supplied by MangaDex. Opening a result currently takes you to the source website; Kurotoon's built-in chapter reader is a separate upcoming milestone.</p></section>}</>}
      {active==='Shop'&&<><Heading eyebrow="A LITTLE EXTRA MAGIC" title="The Shop." description="A dedicated space in the Kurotoon universe, waiting for its rules."/><div className="shop-panel"><div className="shop-sigil"><WandSparkles size={30}/></div><div className="eyebrow">INTENTIONALLY UNDEFINED</div><h2>This space is yours to design.</h2><p>The reward system needs your full explanation before its currencies, actions, progression, or rewards can be designed. Nothing is being guessed or quietly locked in.</p><div className="shop-foot"><Sparkles size={16}/> Reserved for your original reward system</div></div></>}
      {active==='Library'&&<><Heading eyebrow="YOUR PERSONAL COLLECTION" title="Your library." description="Every series you save, every chapter you finish, every place you return to."/><div className="stats"><div><small>COLLECTED</small><strong>—</strong><span>Saved series</span></div><div><small>IN PROGRESS</small><strong>—</strong><span>Stories you're reading</span></div><div><small>UPDATES</small><strong>—</strong><span>New chapters found</span></div></div><EmptyState icon={Library} title="Your collection starts here" text="Once catalog and provider integration is implemented, saved series, progress, categories, and update tracking will live here." action="Explore the browser" onAction={()=>setActive('Browser')}/></>}
      {active==='Me'&&<><Heading eyebrow="YOUR KUROTOON" title="Make it yours." description="The control room for your reading experience, sources, and data."/><div className="profile-card"><div className="profile-avatar">K<span>✦</span></div><div className="profile-copy"><h2>Your space, your rules.</h2><p>Local-first by intention. Your preferences should stay yours.</p></div><small className="profile-state"><i/> FOUNDATION BUILD</small></div><div className="settings-list">{Settings.map(({icon:Icon,title,detail})=><button className="setting-row" key={title} onClick={()=>undefined}><span className="setting-icon"><Icon size={19}/></span><span className="setting-copy"><strong>{title}</strong><small>{detail}</small></span><ChevronRight size={18}/></button>)}</div><div className="settings-note"><ShieldCheck size={16}/> These are planned settings destinations. Their underlying controls will appear as each feature is implemented.</div></>}
      <footer className="footer"><span>KUROTOON <b>✦</b> FOUNDATION BUILD</span><span>Made for the love of stories.</span></footer>
    </div></main>
    <nav className="mobile-nav" aria-label="Mobile navigation">{nav.map(({name,icon:Icon})=><button key={name} className={active===name?'selected':''} onClick={()=>setActive(name)} aria-current={active===name?'page':undefined}><Icon size={19}/><span>{name}</span></button>)}</nav>
  </div>;
}
export default App;