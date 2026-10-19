# KuroToon Decision Log

Record important choices and their evidence here. Decisions can be superseded, but should not disappear silently.

## D-001 — Preserve five primary destinations

**Status:** Accepted  
**Decision:** Keep Home, Browser, Shop, Library, Me in that order. Reader is a dedicated experience/route, not a sixth bottom-nav destination. Plugin/repository management belongs under Me/settings.  
**Reason:** Preserve a simple navigation model and leave space for the core reading flow.  
**Review when:** The product owner explicitly requests a navigation change.

## D-002 — Shop mechanics remain unspecified

**Status:** Accepted / blocked  
**Decision:** Reserve Shop in navigation and the roadmap, but do not invent reward mechanics before the product owner defines them.  
**Reason:** Guessing this system would bake unsupported assumptions into the product.  
**Review when:** The product owner provides the full rules and desired user experience.

## D-003 — Do not promise browser execution of Android extensions

**Status:** Accepted  
**Decision:** Treat Mihon/Tachiyomi APK compatibility as a separate Android feasibility gate. The browser/PWA needs its own provider adapters or a separately validated bridge.  
**Reason:** APK extensions depend on host APIs and Android libraries; downloading a repository index alone does not make extensions executable.  
**Review when:** A working proof of concept demonstrates a technically and legally sound path.

## D-004 — Live-first with bounded cache

**Status:** Accepted direction  
**Decision:** Prefer live streaming and small, explicit cache by default. Keep durable library/progress data separate from disposable media cache.  
**Reason:** The product should be storage-conscious and not silently accumulate large media libraries.  
**Review when:** Real usage and performance measurements establish better defaults.

## D-005 — Catalog identity must preserve edition distinctions

**Status:** Accepted  
**Decision:** Separate Work, Edition, ProviderListing, Chapter, and ChapterListing concepts. Merge only when confidence and evidence are sufficient; preserve provenance and allow user correction.  
**Reason:** Similar titles and chapter numbers do not prove that translations or adaptations are interchangeable.  
**Review when:** Real provider data exposes missing domain concepts.

## D-006 — Initial React web UI and Android runtime

**Status:** Superseded by D-008  
**Historical decision:** React + TypeScript + Vite was the initial prototype UI and Capacitor was an experimental Android packaging route. It is retained in repository history/reference, but is no longer the active Android app architecture.  
**Reason superseded:** The product owner explicitly rejected a website wrapped in Capacitor. A native Flutter/Dart app and APK workflow are now merged to main.

## D-007 — Require build, tests, and dependency-risk checks in CI

**Status:** Accepted; evolve per platform  
**Decision:** Keep CI checks for the legacy web prototype where it remains in the repository, and require Dart formatting/analyze/unit tests plus Flutter analysis/tests and an Android release build for relevant native changes.  
**Reason:** Passing one toolchain's checks does not validate the other runtime; both retained code and the active app need clear validation gates.  
**Review when:** Native CI includes device smoke tests, lockfile/reproducibility checks, release metadata and more comprehensive security checks.

## D-008 — Flutter/Dart is the active native-first application architecture

**Status:** Accepted  
**Decision:** Build the user-facing app with Flutter/Dart in apps/kurotoon_flutter, and keep shared domain policies in packages/kurotoon_core. The Android APK must be built from the Flutter project. Do not substitute a Capacitor/WebView wrapper for the native application. Use platform adapters for OS-specific capabilities and keep domain policy independent of Flutter widgets.  
**Reason:** The product requires a fluid image-heavy comic reader, native lifecycle/audio/files/haptics integration, bounded storage and a common code path across planned platforms. The native build has now passed CI; physical-device acceptance is still outstanding.  
**Review when:** Evidence from real-device profiling or a documented product-owner decision justifies an architecture change.

## D-009 — Community extensions start as declarative manifests

**Status:** Accepted  
**Decision:** Repository indexes may describe individual extensions, but the app only installs declarative JSON manifests whose requests and result mappings are constrained by an explicit schema. Do not execute arbitrary downloaded code or install a repository's entire catalog in one action.  
**Reason:** A familiar repository workflow must not imply unrestricted trust or unproven APK extension compatibility.  
**Review when:** A separate Android compatibility proof of concept has been reviewed for host API, permissions, signatures, licensing and isolation.

## D-010 — Progress must be acceptance-based and candid

**Status:** Accepted  
**Decision:** Track foundation, integration, UI, optional effects, CI and device acceptance separately. Mark work complete only when code/tests/manual evidence meet the acceptance criteria; models and docs alone do not count as a finished end-to-end feature.  
**Reason:** Keep agents aligned and prevent a successful APK build or a set of schemas from being confused with a finished app.  
**Review when:** The product owner changes priorities or a milestone definition.
