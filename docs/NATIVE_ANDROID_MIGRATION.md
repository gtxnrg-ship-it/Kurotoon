# Native Android Migration

## Decision

Kurotoon's intended primary product is a **native Android application**, not a website packaged in a WebView/Capacitor shell. The existing React + TypeScript + Vite codebase is a prototype and product reference. It may inform visual design, domain behaviour, and acceptance tests, but it must not remain the final app's runtime foundation.

Target the native Android engineering model used by mature reader apps such as Mihon: Kotlin, Android SDK APIs, Gradle modules, explicit data/domain boundaries, and a native reader and lifecycle.

## Why

A WebView-based shell can ship an APK, but it does not make the core application native. Kurotoon needs dependable Android lifecycle integration, efficient long-scroll and paged reading, predictable memory use, system navigation, background chapter checks, local storage, audio focus, haptics, and a carefully controlled extension model. These should use platform APIs directly.

## Target stack

- **Language:** Kotlin.
- **UI:** Jetpack Compose with Material 3 as a toolkit, not as a visual reskin. Preserve Kurotoon's own cosmic design language and five destinations.
- **Architecture:** feature-oriented Gradle modules with clear domain, data, core, reader, catalog, sources, and presentation boundaries. Keep dependencies flowing inward; domain logic must not depend on UI or Android framework classes.
- **Async work:** Kotlin coroutines and Flow; structured cancellation and bounded concurrency for source search and page loading.
- **Local persistence:** Room for normalized library/catalog/progress data and DataStore for preferences. Keep media caches bounded and separately managed.
- **Networking/media:** a native HTTP client and an Android image-loading pipeline with request cancellation, retries, bounded preloading, and source-specific policies.
- **Background work:** WorkManager only for work that should survive process death, with user-visible controls and battery-aware constraints.
- **Rendering:** native Compose/Canvas or a purpose-built Android rendering surface for the cosmic environment, with adaptive quality, visibility pausing, reduced-motion support, and profiling on low-end devices.
- **Build/release:** Gradle-based APK generation and GitHub Actions. Development APKs and signed release APKs must be labelled distinctly.

Library choices should be confirmed against current Android compatibility, maintenance, size, and licensing before adding dependencies.

## Non-negotiable constraints

1. The final Android app must not depend on a WebView to render its primary navigation, library, catalog, or reader.
2. Do not delete or discard the existing TypeScript prototype before the native replacement reaches documented parity for the capabilities we choose to carry forward.
3. Preserve the five main destinations in this order: Home, Browser, Shop, Library, Me. The reader is a focused route, not a sixth destination. Source management belongs under Me → Settings.
4. Preserve the product identity and approved cosmic art direction; do not copy Mihon's UI.
5. Live-first and low-storage remain core constraints. Downloads/caches must be explicit, bounded, inspectable, and clearable.
6. A provider failure must not freeze the app or invalidate the whole search. Enforce timeouts, cancellation, per-provider error isolation, rate limits, and concurrency limits.
7. A provider is not an extension runtime. Repository metadata, installable source packages, executable code, and trusted built-in providers are separate concepts.
8. Do not promise direct compatibility with Mihon/Tachiyomi extensions until a proof of concept demonstrates package format, API compatibility, Android version compatibility, permissions, signing/trust, and licensing. Do not execute arbitrary downloaded code without a documented security model.
9. Keep the app content-neutral: providers supply their own content, with source attribution and respect for provider access controls and terms.
10. Update this document and the README whenever the architecture or implementation status changes.

## Migration plan

### Phase A — Native foundation
- Add a real Android Gradle project using Kotlin and Jetpack Compose.
- Establish app identity, theme tokens, navigation, system-bar/edge-to-edge handling, lifecycle, and accessibility foundations.
- Add CI that assembles a native APK without running Vite or Capacitor.
- Keep the existing web build as a prototype/reference workflow only.

### Phase B — Reader vertical slice
- Implement a native series details screen, chapter list, paged reader, vertical webtoon reader, LTR/RTL navigation, page retry, cancellation, bounded preloading, and safe-area/system navigation.
- Add progress persistence and restore using Room.
- Verify search → series → chapters → reading → progress restore on a physical Android device.

### Phase C — Catalog and library
- Port domain models and identity rules into Kotlin with tests before connecting UI.
- Implement the five destinations and persistent Library workflows.
- Preserve editions, translations, source provenance, chapter grouping, and user overrides during duplicate reconciliation.
- Build universal search with bounded concurrency and partial results.

### Phase D — Native provider ecosystem
- Define a versioned provider interface independent of UI.
- Prototype one supported external source and document all compatibility constraints.
- Research Mihon/Keiyoushi source formats and APIs; treat direct executable-extension compatibility as a gated experiment, not an assumed feature.
- Add repository trust, source enable/disable, permissions/capabilities, rate limits, diagnostics, and per-source failure isolation.

### Phase E — Immersion and hardening
- Port the procedural cosmos with adaptive rendering and measured performance.
- Add optional audio, voice, music discovery, and haptics only behind capability interfaces and a shared timeline.
- Validate storage, memory, battery, offline/error behaviour, accessibility, process death, app upgrades, and low-end Android performance.
- Establish signed release builds and a clear APK download path at the top of the README.

## Acceptance gates

The native app is not considered a replacement just because it compiles. At minimum:
- CI assembles a native APK without Node/Vite/Capacitor.
- The primary navigation and reader are native Android UI.
- Search, chapter listing, page loading, retry, chapter switching, and progress restoration work end to end.
- Android back/system navigation, process recreation, and background/foreground transitions behave correctly.
- Automated tests cover catalog identity, chapter reconciliation, repository parsing, progress, cancellation, and bounded concurrency.
- Manual tests on at least one low-end and one mid-range Android device document memory, frame pacing, battery, and network failure behaviour.
- The README clearly separates implemented, verified, planned, and experimental features.

## Current state

**Decision recorded; migration not yet implemented by this document.** The current repository remains React + TypeScript + Vite with Capacitor. Do not describe the native migration as complete until the code and CI prove it.
