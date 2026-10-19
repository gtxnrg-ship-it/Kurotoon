# Kurotoon

<p align="center">
  <strong>A native-first, live-first comic reader with a living Galaxy identity.</strong><br />
  One coherent library across sources — without turning Android into a website wrapper.
</p>

<p align="center">
  <a href="https://github.com/gtxnrg-ship-it/Kurotoon/releases/download/continuous-latest/Kurotoon.apk"><strong>⬇ Download the latest Android APK</strong></a>
  ·
  <a href="https://github.com/gtxnrg-ship-it/Kurotoon/releases">All builds and release notes</a>
  ·
  <a href="https://github.com/gtxnrg-ship-it/Kurotoon/actions/workflows/android-apk.yml">APK build status</a>
</p>

<p align="center">
  <a href="https://github.com/gtxnrg-ship-it/Kurotoon/actions/workflows/android-apk.yml"><img alt="Android APK" src="https://github.com/gtxnrg-ship-it/Kurotoon/actions/workflows/android-apk.yml/badge.svg?branch=main" /></a>
  <a href="https://github.com/gtxnrg-ship-it/Kurotoon/actions/workflows/dart-core.yml"><img alt="Dart Core" src="https://github.com/gtxnrg-ship-it/Kurotoon/actions/workflows/dart-core.yml/badge.svg?branch=main" /></a>
</p>

> **Build type:** the APK is an early Flutter-native development build, not a finished or store-ready product. Back up anything important on your device, install only if you're comfortable testing pre-release software, and report what works or breaks. The stable download link is updated by a successful build from `main`; numbered continuous releases remain available for comparing earlier builds.

---

## Project status — 19 October 2026

**Full-product progress: ~39%** · **Backend foundation: ~55–60%** · **Native UI experience: ~22%** · **CI/APK pipeline: ~90%**

These are honest engineering estimates, not code-line counts or test-coverage percentages. They are reviewed against merged implementation, automated checks and known missing end-to-end workflows. A domain model or database table counts as foundation work, not as a finished user feature. CI being green does not prove the app works on a physical phone.

| Workstream | Estimate | What the number means today |
|---|---:|---|
| Native build and distribution | 90% | The Flutter APK builds in CI and is published; device installation/smoke testing, release metadata and a store-quality release process remain. |
| Dart domain and policy core | 70% | Typed models, matching policies, request coordination, progress reconciliation, cache/effect/voice policies exist; broader adversarial and integration tests remain. |
| Persistent data layer | 55% | SQLite schema and migrations exist for core data; complete wiring of CRUD flows into the Flutter UI and failure/recovery tests remain. |
| Providers and live source runtime | 50% | MangaDex and bounded provider contracts exist; full source health, pacing, schema-drift handling and more sources remain. |
| Repository/extension foundation | 65% | Preview, checks, integrity gates, install records and declarative manifests exist; a complete repository/extension UI and compatibility testing remain. |
| Cross-source catalog | 45% | Identity matching, source provenance and chapter/edition concepts exist; persisted multi-source reconciliation, corrections/undo and creator pages remain. |
| Native reader and library | 20% | Some domain/storage groundwork exists; Flutter-native chapter reading, full progress resume, library management and edge-case UX remain. |
| Galaxy performance/accessibility | 25% | The initial animated shell exists; reduced-motion/lifecycle hardening and real frame/memory/battery profiling remain. |
| Voice, music, haptics and particles | 10% | Some policy models exist; the optional native runtime, controls, packs and lifecycle integration are largely future work. |
| Other platform releases | 10% | Shared Dart direction is established; iOS/iPadOS/Windows/Linux adapters and verified builds remain. |

For acceptance criteria and the next implementation queue, see [the roadmap](docs/ROADMAP.md). The percentages must move only when code/tests/manual acceptance evidence changes; they must not be increased merely because documentation was added.

## What is real in the current build?

### Implemented and merged

- Native Flutter/Dart Android shell — the active APK is built from `apps/kurotoon_flutter`, not from a website wrapped in Capacitor.
- Five primary destinations in the required order: **Home · Browser · Shop · Library · Me**. The Reader is a separate route, not a sixth bottom tab.
- Initial animated Galaxy treatment with a dark, space-like visual foundation.
- Browser search wired to the provider coordinator and built-in MangaDex adapter.
- Built-in MangaDex enable/disable capability and persisted provider settings in the runtime.
- Pure Dart core package for catalog/domain rules, provider coordination, cancellation, progress reconciliation, storage planning, extension policies and optional-effect policies.
- SQLite schema/migrations for works, source listings, editions, chapters, library entries, progress, settings, creator credits, identity review, cache metadata, voice-pack install metadata, repository definitions and installed declarative extensions.
- A repository/extension service foundation with preview-before-add APIs, index/manifest validation, size/digest checks, response limits, request timeouts, cancellation, HTTPS and host checks, and redirects rejected.
- GitHub Actions for Dart core validation, Flutter analysis/tests and a native release APK build. On the current native merge, the APK build and Dart core CI completed successfully.

### Still incomplete — please do not mistake the shell for the finished product

- The Flutter Reader is not yet the complete search → series → chapter list → page reading experience.
- Library and Shop are reserved destinations; the real library CRUD/sorting/update experience is not complete, and Shop mechanics are intentionally undefined.
- The full Me → Settings → Repositories → extension detail/install/update/disable/remove UI is not yet fully wired end-to-end.
- Multi-source reconciliation, manual identity correction/undo, creator/artist pages and reliable mini-chapter grouping are not complete as full user workflows.
- Haptics, voice packs, synchronized narration/dialogue, atmospheric music discovery/playback and particle mechanics are not fully wired native features.
- Physical Android installation, older/lower-end device performance, lifecycle/audio-focus behaviour, accessibility, crash recovery and battery use have not yet been signed off.
- iOS/iPadOS/desktop targets are architectural goals, not verified deliverables.

## Product north star

Kurotoon should feel like **one premium, fast, thoughtfully atmospheric library**, not a pile of unrelated source scrapers. Ordinary reading must be excellent without AI, audio, network extras or animated effects. Everything cinematic is optional and must never block the page the user is trying to read.

### Navigation contract

Keep this exact order unless the product owner changes it:

1. **Home** — continue reading, recent activity and calm discovery.
2. **Browser** — cross-source search, filters and attributable results.
3. **Shop** — reserved until its rules are defined; do not invent coins, streaks, prices, tasks, monetization or rewards.
4. **Library** — saved works, statuses, categories, sorting, update tracking and stable progress.
5. **Me** — settings, repositories/extensions, storage, appearance, reader/audio/voice/effects preferences and diagnostics.

Repositories and settings must not become extra permanent bottom-nav destinations. Opening a work leads to work details; opening a chapter enters a dedicated Reader experience.

## Visual identity: the Galaxy theme

Galaxy is an identity, not a generic web dashboard or a pile of glowing cards.

- **Foundation:** dark, readable surfaces; deep indigo/blue-violet space tones; luminous but restrained accent colours; subtle gradients and depth.
- **Motion:** slow drifting stars/nebulae, layered parallax where appropriate, restrained particles and gentle transitions. Avoid constant high-frequency flashing or distracting movement.
- **Dynamic colour:** the atmosphere may shift over time, but foreground contrast and semantic states remain stable and accessible. Content colours must never make text or controls unreadable.
- **Hierarchy:** comic covers and page art stay the main content. Galaxy elements live behind the interface and never obscure panels or controls.
- **Touch:** large reliable targets, predictable gestures, safe areas, keyboard/screen-reader semantics and visible focus when relevant.
- **Quality levels:** Full / Reduced / Off (or equivalent), with sensible adaptation under load. Reduced motion and system preferences must be respected.
- **Lifecycle:** stop or reduce unnecessary animation when the app is backgrounded, a surface is not visible, the user enters a distraction-free reader mode or the device is under pressure.
- **Performance:** avoid unbounded animation controllers, rebuild storms, expensive full-screen blur, per-frame allocations and expensive work on the UI isolate.

The current Galaxy rendering is only the first shell pass. The final quality bar requires measurement on real lower-end and mid-range Android hardware. The 60 FPS target is an acceptance goal, not a claim of measured performance.

## Technical architecture

```text
apps/kurotoon_flutter/
  Flutter app, navigation, runtime composition, UI and platform adapters
             |
             v
packages/kurotoon_core/
  Domain models, identity policies, provider contracts, safety and budgets
             |
     +-------+--------+-----------------+
     |                |                 |
  Providers        SQLite         Managed files
  MangaDex +       user state      bounded media/cache/
  declarative      and metadata    installed manifests
  JSON sources
```

### Runtime layers

- **UI:** renders state and dispatches actions; avoid embedding security or catalog rules in widgets.
- **Runtime/application services:** compose providers, persistence, repository workflows and platform capabilities.
- **Pure Dart domain:** deterministic models, validation, identity matching, progress reconciliation, cache/effect policy and provider coordination.
- **Persistence adapter:** SQLite for durable metadata and user-owned data; managed files for larger bytes.
- **Provider adapter:** bounded requests that expose explicit status, timeouts and cancellation.
- **Platform adapters:** actual OS-specific lifecycle, audio focus, speech, haptics, file and notification behaviour.

The “backend” today is mainly on-device domain logic, SQLite and provider services. **There is no hosted application server, cloud account or multi-device sync service.** Do not document one as if it exists.

### Repository map

| Path | Responsibility |
|---|---|
| `apps/kurotoon_flutter/` | Active Flutter app, runtime, SQLite adapter and repository/extension service |
| `packages/kurotoon_core/` | Platform-independent Dart domain and policy package |
| `docs/PRODUCT_VISION.md` | Product north star and experience rules |
| `docs/ARCHITECTURE.md` | Adopted architecture, boundaries, security and performance goals |
| `docs/DART_BACKEND_FOUNDATION.md` | Backend invariants, integrated services and verification gaps |
| `docs/DATA_FOUNDATION.md` | SQLite schema, storage boundaries and privacy guarantees |
| `docs/EXTENSION_REPOSITORIES.md` | Repository/index/manifest format and safety gates |
| `docs/DECISIONS.md` | Accepted/replaced architecture decisions |
| `docs/ROADMAP.md` | Workstream percentages, phases, acceptance gates and next tasks |
| `.github/workflows/android-apk.yml` | Native Android release build, checksum and APK release publishing |
| `.github/workflows/dart-core.yml` | Core format/analyze/unit-test CI |

## Backend: requirements and invariants

### Provider runtime

- Each source declares capabilities; not all sources necessarily support details, chapters, reader pages or creator pages.
- Bound active source requests and every request deadline. Propagate cancellation to the underlying network operation when possible.
- Report empty, partial, blocked, rate-limited, malformed, timed-out, cancelled and unsupported results as different states.
- Use bounded response sizes and pagination, prevent retry storms, and respect source-specific terms/access rules.
- Preserve source IDs, canonical URLs, language, publication/verification timestamps and attribution.
- MangaDex is the first built-in/live source, but the rest of the application must remain source-agnostic. Users can disable it without treating it as an uninstallable community extension.

### Universal catalog and identity

Never treat a provider URL as the global identity of a series.

- **Work:** logical story/one-shot.
- **Edition:** language, adaptation, season, publisher or other meaningful release variant.
- **Provider listing:** source-specific title, URL, identifier and metadata.
- **Chapter:** logical reading unit where evidence supports the link.
- **Chapter listing:** specific translation/release from a provider.
- **Creator credit:** creator identity and role, retaining source attribution and uncertainty.
- **Review candidate:** possible duplicate that is not safe to auto-merge.

Title similarity alone is insufficient. Conflicting publication year, format, language, adaptation or source IDs should lower confidence or veto automatic matching. Manual corrections must be persistent, reversible and must not silently rewrite stable library/progress keys.

Chapter logic must preserve specials, seasons, one-shots, doujin structure and mini-chapters. A bundle of six mini-chapters must not be presented as six normal full chapters without context. When multiple translations exist, show the latest useful release and keep language, group, provider and freshness attributable.

### SQLite, progress and local storage

- The current SQLite schema version is 2. Database migrations must be explicit, ordered and tested from previous versions.
- Keep library, settings, progress and review decisions separate from disposable cover/page/provider/audio cache.
- The default cache *planning* budget is 1.5 GiB. This does not mean all app data has a strict 1.5 GiB cap or that every write is already routed through eviction.
- Protect pinned/offline user-owned content. An eviction plan must never delete library or reading progress.
- Store media bytes in managed files, not database blobs. Bound downloads, write via temp files and clean up after failures.
- When persistence is unavailable, report it honestly; transient memory state must not be presented as durable.
- No reading history or user library should be uploaded to a server by default.
- Any future export/import must be versioned, validated, user-initiated and previewed before data can be overwritten.

### Extension ecosystem

The intended user journey is **repository → browse extensions → inspect one → install one → enable/disable/update/uninstall**. A repository index is a catalogue, not permission to install everything it lists.

- Accept HTTPS repository URLs only; reject credentials, custom ports, fragments and known local/private hosts.
- Check DNS-resolved addresses; do not follow redirects to another origin. A URL allow-check is not a complete defence against all DNS-rebinding/network races.
- Cap index/manifest/response sizes; count actual received bytes rather than trusting Content-Length.
- Verify index-declared size and SHA-256 and cross-check manifest ID, version, minimum app API and capabilities.
- Preview repository identity and obtain explicit confirmation. If the index changes after preview, ask the user to review again.
- Start with declarative JSON manifests and constrained endpoint/path/field mappings. Do not execute arbitrary downloaded code with full app privileges.
- Show license, maintainer, capabilities, domains, content rating where available, version, digest and failure reason.
- Treat Mihon/Tachiyomi APK compatibility as a separate Android research gate. A repository index download does not prove that its APK extensions can run in Kurotoon.

See [extension repository format and safety rules](docs/EXTENSION_REPOSITORIES.md) before changing the schema.

## Reader requirements — the core of the product

The Reader must be reliable before cinematic extras are considered done.

- Native Flutter reader route; do not use a WebView as the core reading surface.
- Support paged manga and long-strip webtoon/manhwa layouts.
- Lazy mounting/virtualize long chapter content; bound image decoding, neighbor prefetch and network concurrency.
- Cancel stale page/chapter work when navigating away and expose retry for failed pages.
- Save and restore per-work/edition/chapter position, including the appropriate page anchor or vertical-scroll fraction.
- Implement previous/next chapter navigation with clear boundary behaviour, plus reading direction/layout/fit/spacing and data-saver controls.
- Handle safe areas, screen rotation, system bars, app background/foreground, low memory, slow networks, malformed images and very long chapters.
- Keep the source and edition visible; do not pretend missing pages or network failures are valid content.
- The reader must be fully useful when audio, narration, particles and all other effects are disabled.

Acceptance flow: **search → series details → chapter list → open reader → read pages → retry a failed page → change chapter → close/reopen → resume at the expected position.** This is not yet a finished Flutter-native flow.

## Library and discovery requirements

- Durable statuses: reading, completed, planned, paused, dropped and rereading; user changes must survive app restarts/source removals.
- Auto/manual sort, filters, custom categories/collections, continue-reading and last-opened tracking.
- Merge provider observations without duplicating the same work when matching is supported by evidence.
- Preserve language/adaptation/edition distinctions where works are not interchangeable.
- Creator pages aggregate works from multiple sources while retaining source evidence and identity ambiguity.
- Update notifications must deduplicate releases and respect per-source mute/disable controls.
- Shop stays a reserved tab until mechanics are supplied; do not invent economy or monetization rules.

## Optional voice, music, haptics and particles

These are **planned integration work**, not complete features merely because policy models exist.

- **Voice:** optional open-source/local speech packs, explicit license acceptance, size/free-space checks, SHA-256 verification, cancellable install/remove and clear storage accounting.
- **Dialogue/narration:** OCR, reading order, speaker attribution, emotion and timing are uncertain inference. Store confidence and allow correction; never silently treat a guess as canon.
- **Music discovery:** a browser-native atmospheric discovery/player concept that remains user-controlled, source-attributed and lifecycle-aware. No surprise autoplay or unbounded media extraction.
- **Haptics:** native adapter, system preference checks, rate limits and no vibration on every tiny scroll event.
- **Particles:** adaptive quality, reduced-motion support, lifecycle pause and a global off switch. The reading path must not depend on particles.
- **Audio session:** global stop/mute, separate volume controls for music/ambience/voices/effects, focus handling, no unexpected loud startup and cleanup when the reader closes/backgrounds.

## Performance and quality bar

These are targets until measured and recorded.

- Aim for smooth 60 FPS on ordinary devices; gracefully reduce Galaxy motion under load and on lower-end hardware.
- Keep network and expensive disk operations off the UI isolate.
- Bound provider concurrency, page prefetch, decode work, response bytes, file cache and voice model size.
- Pause background/unseen animations, respect reduced motion and dispose controllers.
- Virtualize long lists/chapters; avoid unbounded queues, controller leaks and expensive full-screen blur.
- Measure cold start, time-to-first-search-result, time-to-first-reader-page, scroll frame pacing, peak memory, cache growth, heat and battery use on actual devices.
- Test narrow phones, tablets and desktop layouts; large text, keyboard/screen-reader access; old three-button and modern gesture navigation.
- Fail safely: unavailable source, offline mode, storage-full, app kill during write, invalid manifest and corrupt cache must not lose user-owned data.

## Build, test and download

### Download a build

1. Open **[Download latest Android APK](https://github.com/gtxnrg-ship-it/Kurotoon/releases/download/continuous-latest/Kurotoon.apk)**.
2. On Android, review the install prompt and allow installs from the chosen download app only if you trust this development build.
3. Keep in mind this APK has passed CI build/tests, but it has not been certified by a store or signed as a production release.
4. Use the release page for previous numbered builds and release notes.
5. Verify the APK with the published `Kurotoon.apk.sha256` checksum where available.

### CI

- [Android APK workflow](https://github.com/gtxnrg-ship-it/Kurotoon/actions/workflows/android-apk.yml) — Flutter dependency resolution, analysis, tests, release APK build, artifact upload, checksum and main-branch development release.
- [Dart Core workflow](https://github.com/gtxnrg-ship-it/Kurotoon/actions/workflows/dart-core.yml) — core formatting, static analysis and unit tests.
- Each main-branch successful Android workflow publishes a numbered `continuous-N` release and updates `continuous-latest` for a stable direct APK URL. Version tags matching `v*` publish a versioned release.

Workflow artifacts are temporary (currently 14 days); the release asset is the better user-facing download surface.

### Local commands

Install a current stable Flutter SDK and Dart SDK, then run:

```bash
# Pure Dart domain package
cd packages/kurotoon_core
dart pub get
dart format --output=none --set-exit-if-changed lib test
dart analyze
dart test

# Flutter application
cd ../../apps/kurotoon_flutter
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The CI workflow generates an Android platform scaffold before running the release build because the platform project is generated in CI. To reproduce the workflow exactly, follow [.github/workflows/android-apk.yml](.github/workflows/android-apk.yml). A local Android build also requires the Flutter Android toolchain and Android SDK.

No secrets or personal tokens belong in the repository. The application currently does not require a cloud API key.

## Milestone definition for the progress number

The full-product percentage weights the intended end-user outcome—not file count. Current approximate workstream scores and weights:

| Workstream | Weight | Current completion estimate |
|---|---:|---:|
| Native build and release delivery | 5% | 90% |
| Domain models and policies | 10% | 70% |
| Provider runtime and live sources | 10% | 50% |
| Persistence and extension safety | 10% | 60% |
| Cross-source catalog and data integration | 15% | 45% |
| Reader and library end-to-end | 30% | 20% |
| Galaxy polish, effects and accessibility | 10% | 25% |
| Voice/music/haptics/particle integrations | 10% | 10% |

Using the explicit weights above, the current weighted product score is approximately **39%** (38.75 before rounding). This deliberately gives the end-to-end Reader and Library more weight than foundational code. Backend foundations are roughly 55–60% because more policy/data groundwork exists than is wired into complete user journeys. Recalculate when implementation or acceptance evidence changes; do not change the score simply to make the number look better.

## Hand-off instructions for future agents

Read in this order:

1. [Product vision](docs/PRODUCT_VISION.md) — what the user experience should feel like and must preserve.
2. [Architecture](docs/ARCHITECTURE.md) — active Flutter/Dart boundaries, safety and performance invariants.
3. [Roadmap](docs/ROADMAP.md) — current progress estimates, phases and acceptance gates.
4. [Backend foundation](docs/DART_BACKEND_FOUNDATION.md) and [data foundation](docs/DATA_FOUNDATION.md) — implemented foundation versus missing integration.
5. [Extension format](docs/EXTENSION_REPOSITORIES.md) — repository/manifest rules.
6. [Decision log](docs/DECISIONS.md) — accepted decisions and superseded proposals.

Rules every agent must follow:

- Keep Flutter/Dart as the active native app; do not reintroduce a Capacitor/WebView wrapper as the Android product.
- Preserve Home / Browser / Shop / Library / Me and keep repository management under Me/settings.
- Treat Galaxy as a cohesive background/interaction identity, but readability, battery and reader quality come first.
- Never report a planned feature as implemented only because a model/schema exists.
- Add focused unit tests with policy changes, migration tests with database changes and integration evidence for network/platform code.
- Keep source attribution; do not merge works on title alone; don't silently erase user data.
- Keep cache bounds separate from library, progress, settings and pinned offline data.
- Treat repository content as untrusted. Declarative manifests only until a separately reviewed extension execution architecture exists.
- Do not claim native voice/music/haptics/particles, cloud sync, all-platform support, or 60 FPS performance without real integration and evidence.
- Keep Shop reserved until its mechanics are explicitly specified.
- Update the README status, this roadmap and the decision log when the implementation direction or acceptance state changes.

## Documentation index

- [Architecture](docs/ARCHITECTURE.md)
- [Product vision](docs/PRODUCT_VISION.md)
- [Roadmap and progress tracker](docs/ROADMAP.md)
- [Dart backend foundation](docs/DART_BACKEND_FOUNDATION.md)
- [Local-first data foundation](docs/DATA_FOUNDATION.md)
- [Extension repositories](docs/EXTENSION_REPOSITORIES.md)
- [Universal catalog](docs/UNIVERSAL_CATALOG.md)
- [Universal search](docs/UNIVERSAL_SEARCH.md)
- [Decision log](docs/DECISIONS.md)
