# KuroToon Decision Log

Record important choices and their evidence here. Decisions can be superseded, but should not disappear silently.

## D-001 — Preserve five primary destinations

**Status:** Accepted  
**Decision:** Keep Home, Browser, Shop, Library, Me in that order. Reader is a dedicated experience/route, not a sixth bottom-nav destination. Repository and extension management live under Me/settings.  
**Reason:** Preserve a simple navigation model and leave space for the product's core reading flow.  
**Review when:** The product owner explicitly requests a navigation change.

## D-002 — Shop mechanics remain unspecified

**Status:** Accepted / blocked  
**Decision:** Reserve Shop in navigation and the roadmap, but do not invent reward mechanics before the product owner defines them.  
**Reason:** Guessing this system would bake unsupported assumptions into the product.  
**Review when:** The product owner provides the full rules and desired user experience.

## D-003 — Do not promise browser execution of Android extensions

**Status:** Accepted  
**Decision:** Treat Mihon/Tachiyomi APK compatibility as a separate Android feasibility gate. The browser/PWA will require its own provider adapters or a separately validated bridge.  
**Reason:** APK extensions depend on host APIs and Android libraries; downloading a repository index alone does not make the extensions executable.  
**Review when:** A working proof of concept demonstrates a technically and legally sound path.

## D-004 — Live-first with bounded cache

**Status:** Accepted direction  
**Decision:** Prefer live streaming and a small, explicit cache by default. Keep durable library/progress data separate from disposable media cache.  
**Reason:** The product should be storage-conscious and not silently accumulate large media libraries.  
**Review when:** Real usage and performance measurements establish better defaults.

## D-005 — Catalog identity must preserve edition distinctions

**Status:** Accepted  
**Decision:** Separate Work, Edition, ProviderListing, Chapter, and ChapterListing concepts. Merge only when confidence and evidence are sufficient; preserve provenance and allow user correction.  
**Reason:** Similar titles and chapter numbers do not prove that translations or adaptations are interchangeable.  
**Review when:** Real provider data exposes missing domain concepts.

## D-006 — Select the shared web UI foundation; keep Android runtime open

**Status:** Accepted for the initial UI; Android decision remains open  
**Decision:** Use React + TypeScript + Vite for the initial shared web UI. Do not yet lock PWA packaging or Android runtime architecture until extension compatibility, reader performance, and audio lifecycle feasibility are tested.  
**Reason:** The first app shell is now built and CI-verified, while Android extension compatibility remains the highest-risk platform assumption.  
**Next action:** Compare a shared web UI with native Android integration against a more native Android path using a real extension/audio proof of concept.

## D-007 — Require build, tests, and high/critical dependency audit in CI

**Status:** Accepted  
**Decision:** Pull requests must run the TypeScript production build, domain unit tests, and an npm audit that fails on high or critical vulnerabilities. Use patched Vite and Vitest releases.  
**Reason:** The first dependency audit exposed critical/high findings in the initial toolchain; upgrading the toolchain produced a clean audit and prevented the unsafe versions from becoming the baseline.  
**Review when:** CI grows to include additional platforms, dependency lockfile verification, and more comprehensive security checks.