# KuroToon 🌌

> **[⬇️ Download the latest Android APK](https://github.com/gtxnrg-ship-it/Kurotoon/releases/download/continuous-latest/Kurotoon.apk)** · [All releases](https://github.com/gtxnrg-ship-it/Kurotoon/releases) · [Build history](https://github.com/gtxnrg-ship-it/Kurotoon/actions/workflows/android-apk.yml)

**KuroToon is being built as a native Flutter/Dart app—not a website wrapped in Capacitor.** The APK link points to the stable continuous-latest release alias, updated by successful main-branch builds. It is a development build; install and test it on your device before relying on it.

A live-first manga, manhwa, manhua and webtoon reader set inside a living, evolving cosmic universe. The goal is a lightweight, polished reading app with a unified multi-source catalog, a durable user-owned library, safe repositories/extensions, and optional synchronized voice, audio, music and haptics.

---

## 🚦 Project dashboard

**Last roadmap checkpoint:** 19 October 2026  
**Overall product estimate:** **~40%**  
**Backend foundation estimate:** **~55–60%**

These are engineering estimates based on the roadmap and implementation evidence—not code-line counts, automated coverage, or a claim that the product is almost finished. Backend models and safety policies count as foundation work; a feature is not considered complete until its real app flow is integrated and tested.

| Workstream | Estimate | What exists today | Main remaining gate |
|---|---:|---|---|
| Native build and CI | 90% | Flutter/Dart app, analysis/tests, release APK workflow | Physical-device install, smoke tests, release/signing policy |
| Dart domain and policy core | 70% | Typed catalog/provider models, identity matching, cancellation, progress and effect/voice policies | More adversarial tests and full end-to-end consumers |
| Persistence | 55% | SQLite schema/migrations and data models for catalog, library, progress, settings, repositories and extensions | Verify integrated CRUD, migration recovery and restart/crash handling |
| Providers | 50% | Native MangaDex adapter, provider contracts, bounded search coordination | On-device live flow, rate-limit/health handling, more adapters |
| Repository/extension foundation | 65% | Repository/manifest validation, preview-before-add, hash/size checks, persistent records | Full repository UI, install/update/remove recovery and compatibility proof |
| Cross-source catalog | 45% | Work/edition/listing concepts, conservative matching and grouping policies | Persisted merge pipeline, undo/corrections, artist pages and real fixtures |
| Native reader and library | 20% | Domain/persistence foundation and earlier prototype evidence | Flutter-native chapter reader, page loading, progress resume, full library UI |
| Galaxy and adaptive performance | 25% | Initial animated native shell and effect-budget policy | Lifecycle/reduced-motion hardening and real device profiling |
| Voice, music, haptics and particle runtime | 10% | Timeline/policy foundations and voice-pack safety constraints | Actual platform adapters, UI, playback, pack lifecycle and device tests |
| Other platform releases | 10% | Shared Dart core intended to be portable | iOS/iPadOS/Windows/Linux host integration and validation |

**How to read this:** the foundation is ahead of the end-user experience. A green CI run proves that the tested code builds and its automated tests pass; it does not prove real-source reliability, phone performance, or complete feature wiring.

For the detailed acceptance checklist, see the [Roadmap](docs/ROADMAP.md).

### How the headline percentage is calculated

The headline score is weighted by end-user value and remaining integration work, not by the number of files. The weights below sum to 100%; a policy model or schema only earns foundation credit until the feature is wired through its real user flow.

| Workstream | Weight | Estimate | Weighted points |
|---|---:|---:|---:|
| Native build and release delivery | 5% | 90% | 4.50 |
| Domain models and policies | 10% | 70% | 7.00 |
| Provider runtime and live sources | 10% | 50% | 5.00 |
| Persistence and extension safety | 10% | 60% | 6.00 |
| Cross-source catalog integration | 15% | 45% | 6.75 |
| Reader and library end-to-end | 30% | 20% | 6.00 |
| Galaxy polish and accessibility | 10% | 25% | 2.50 |
| Voice/music/haptics/particle runtime | 10% | 10% | 1.00 |
| **Total** | **100%** | — | **38.75%** |

The precise weighted estimate rounds to **39%**; the dashboard displays this as **~40%** for readability. Backend foundations are estimated at 55–60% because the policy/data groundwork is ahead of complete app workflows. This is a manually reviewed engineering estimate, not test coverage and not a claim of device readiness.


## 🎯 Product direction

- **Native first:** Flutter/Dart for the cross-platform app and domain core, with platform adapters for native capabilities. No Capacitor-wrapped website as the target architecture.
- **Live-first and storage-conscious:** small bounded caches, explicit downloads only, and clear separation between durable user data and disposable media cache.
- **One catalog, many sources:** group confidently matched works without erasing editions, translations, chapter variants, or source provenance.
- **A living Galaxy:** procedural, layered, colour-shifting cosmic motion that adapts to device capability and never compromises reading.
- **Immersion is optional:** voice, soundtrack, ambient audio, effects and haptics share a timeline model but can all be disabled independently.
- **No fake completion:** planned, in-progress, implemented and verified are separate statuses.
- **User-owned library:** core reading and local library data should not require an account or default cloud sync.

## 🧭 Main navigation

Keep the five primary destinations in this order:

1. **Home** — continue reading, recent activity, discovery and updates.
2. **Browser** — unified source search, filters, series and creator pages.
3. **Shop** — reserved for future mechanics; do not invent currencies, prices or reward loops.
4. **Library** — saved works, statuses, collections, sorting, history and progress.
5. **Me** — settings, storage/privacy, repositories/extensions, reader preferences, audio/voice/haptics and diagnostics.

The reader is a focused route, not a sixth tab. Repository and extension controls belong under **Me → Settings**. Preserve approved assets and the existing KuroToon visual identity.

## 🪐 Galaxy experience and performance

The cosmic environment should feel like a coherent, endless universe—not a generic gradient with random particles.

- Deep navy, midnight blue, cyan and restrained violet lead the palette.
- Layered nebulae, stars, distant galaxies, filaments and subtle planetary silhouettes establish depth.
- Slow ambient drift, parallax and touch-reactive space-bending create a shared sense of motion.
- Stable procedural seeds can keep each installation's universe distinctive and coherent.
- Respect reduced motion, battery saver, app visibility and manual quality settings.
- Bound particles, blur, image preloading, animation work, caches and network concurrency.
- Never allow cosmic effects to obscure comic artwork or delay page turns and navigation.
- Do not promise a frame rate, battery impact or low-end-device smoothness until measured on real hardware.

## 📚 Reader and catalog requirements

The intended end-to-end flow is **search → series → chapters → read → save progress → resume**.

The reader must support reliable chapter navigation, paged and long-strip/webtoon layouts, safe image loading, bounded preloading, retry/recovery, reading direction, accessible controls and progress restoration. The Flutter-native reader is still a major implementation gate.

Catalog rules:

- Separate a logical **Work**, an **Edition**, a source-specific **Provider listing**, a logical **Chapter**, and a source-specific **Chapter listing**.
- Match using multiple evidence signals. Title-only similarity must never silently merge unrelated works.
- Preserve source, language, translation, release-group and edition provenance.
- Handle specials, seasons, one-shots, doujin structure and mini-chapters carefully; six mini-chapters should not automatically appear as six ordinary full chapters.
- Make merges reversible and retain user-approved corrections.
- Show partial results and source errors honestly; a timeout is not an empty result.
- Creator/artist pages should aggregate versions across available providers without inventing identities or credits.

MangaDex remains an additive, disableable provider—not the entire product. Additional providers should be added only with tested adapters, bounded requests and source-specific rules respected.

## 🧩 Repositories and extensions

The target experience is repository → extension → source management, familiar to users of extension-based readers, with a KuroToon-native UI and safety model.

Planned user flow:

1. Add a repository by supported deep link or manual HTTPS URL.
2. Inspect its identity, metadata, version, capabilities and trust warnings before adding it.
3. Browse extensions and review compatibility, source, permissions and license information.
4. Install, enable, update, disable or remove an extension with clear progress and error states.
5. Recover safely from invalid metadata, failed downloads, interrupted updates and stale repository information.

Safety requirements include strict URL and redirect validation, bounded downloads, digest/size verification, cancellation, no unrestricted execution of untrusted code, rate limits and useful diagnostics. Repository metadata is **not** the same thing as an executable extension runtime. Mihon/Tachiyomi APK compatibility must not be claimed until a real native host/API proof of concept works. Browser/PWA extensions and Android-native extensions are different compatibility targets.

## 💾 Backend, data and storage

The architecture is local-first by default. Keep durable user data separate from disposable cache.

**Durable data:** library membership, reading state, categories/order, progress, source preferences, identity corrections and user-approved media/voice corrections.

**Disposable data:** thumbnails, temporary search results, page cache, temporary OCR output and generated audio cache.

The backend foundation includes typed domain contracts, provider coordination, conservative identity matching, SQLite persistence/migrations, repository/manifest validation and policy models. Remaining integration work includes full CRUD flows, restart/crash recovery, migration fixtures, storage-budget enforcement, source health/backoff, diagnostics export with redaction, and explicit backup/import/export flows.

Downloads must be explicit, cancellable and visible in storage management. Clearing media cache must not erase library or reading progress. Do not silently accumulate gigabytes of comic pages, audio or artwork.

## 🎧 Voice, music, haptics and particles

These features should share a **Reader Timeline / Event Model**, rather than behave like unrelated effects.

- Independent controls for music, ambience, sound effects, dialogue, narration, character voice and haptic intensity.
- Global pause/mute, safe volume defaults, no unexpected autoplay and cancellation on chapter changes.
- Haptics are brief, optional, capability-aware and tied to meaningful user-approved events—not every scroll or particle.
- Voice packs need license metadata, size limits, checksums, cancellable downloads, safe extraction and removal.
- OCR, bubble order, speaker, emotion and timing are uncertain inferences; show confidence and allow correction.
- Most static comics do not contain trustworthy panel-level timing. Never claim perfect automatic synchronization without suitable cue data.
- Music discovery must respect source rules and access controls. Never bypass DRM, authentication or paywalls.
- All immersive features must be opt-in, independently disableable and irrelevant to the reliability of ordinary reading.

The current foundation/policy work does **not** mean the complete voice runtime, music engine, haptic synchronization or all particle mechanics are wired up. Those remain explicit implementation gates.

## 🗺️ Implementation roadmap

- [x] **Phase A — Native foundation:** Flutter/Dart app, CI analysis/tests and release APK pipeline.
- [ ] **Phase B — Backend reliability:** finish runtime integration, provider cancellation/backoff, migration and crash recovery, storage enforcement and redacted diagnostics.
- [ ] **Phase C — Repository ecosystem:** complete repository/extension UI, installation lifecycle, update/rollback and compatibility validation.
- [ ] **Phase D — Universal catalog and library:** persisted cross-source matching, correction/undo, translation-aware chapters, creator pages and complete library CRUD.
- [ ] **Phase E — Native reader:** search-to-reading vertical slice, reliable image loading, chapter navigation and resume.
- [ ] **Phase F — Galaxy and polish:** adaptive rendering, accessibility, lifecycle handling and physical-device performance profiling.
- [ ] **Phase G — Immersive layer:** real audio/voice/haptic adapters, pack lifecycle, music discovery and particle controls.
- [ ] **Phase H — Platform/release acceptance:** device matrix, accessibility/security review, stable releases and checksums.

The checkbox means its acceptance gate is met—not merely that a class, screen or plan exists. Phase A is not the same as a finished product. See [docs/ROADMAP.md](docs/ROADMAP.md) for the detailed checklist and workstream estimates.

## 📦 Download and install

### Android APK

**[Download Kurotoon.apk](https://github.com/gtxnrg-ship-it/Kurotoon/releases/download/continuous-latest/Kurotoon.apk)**

- The stable continuous-latest URL is intended to track the latest successful main-branch development build.
- [Browse all releases](https://github.com/gtxnrg-ship-it/Kurotoon/releases).
- [Inspect Android build runs](https://github.com/gtxnrg-ship-it/Kurotoon/actions/workflows/android-apk.yml).
- If the direct link is temporarily unavailable, open the build history and select a successful run; workflow artifacts have limited retention.
- Development APKs are for testing, not a claim of production-store signing or release readiness. Android may ask you to confirm installation from your chosen source.

### Build locally

Requirements: a compatible stable Flutter SDK, Dart SDK supplied by Flutter, and Android SDK/tooling for Android builds.

    cd apps/kurotoon_flutter
    flutter pub get
    flutter analyze
    flutter test
    flutter build apk --release

The shared Dart core lives in packages/kurotoon_core. Follow the CI workflows as the source of truth for the complete repository checks.

## 🧪 Verification rules

1. Automated tests must pass on the exact commit being reported.
2. A build artifact proves packaging, not physical-device stability or performance.
3. Test provider failures, cancellation, malformed metadata, storage errors and app restart—not only happy paths.
4. Keep a reproducible build/commit reference with each reported APK.
5. Do not mark a feature verified without its stated acceptance evidence.
6. Update this README and the roadmap when implementation status changes.

## 🧰 Handoff contract for future agents

Read these files before making architectural changes:

1. [Product vision](docs/PRODUCT_VISION.md) — experience pillars and non-goals.
2. [Architecture](docs/ARCHITECTURE.md) and [decision log](docs/DECISIONS.md) — current accepted boundaries and superseded decisions.
3. [Roadmap](docs/ROADMAP.md) — progress estimates, concrete gaps and acceptance gates.
4. [Backend foundation](docs/DART_BACKEND_FOUNDATION.md) and [data foundation](docs/DATA_FOUNDATION.md) — implemented services versus integration gaps.
5. [Extension repositories](docs/EXTENSION_REPOSITORIES.md) — supported index/manifest format and trust limits.

Non-negotiable rules:

- Keep Flutter/Dart as the active native app; do not replace it with a Capacitor/WebView wrapper.
- Preserve Home → Browser → Shop → Library → Me, with Reader as a separate route and repository controls under Me/settings.
- Treat Galaxy motion as optional atmosphere. Reader legibility, battery, accessibility and low-end-device responsiveness come first.
- Keep MangaDex disableable; do not let its schema or IDs become the global catalog model.
- Never auto-merge series by title alone. Retain provenance, editions, translation details, and user correction/undo pathways.
- Treat repositories and manifests as untrusted input. Do not execute arbitrary downloaded code or install all extensions when a repository is added.
- Keep library, preferences, reading progress and pinned offline items out of disposable-cache eviction.
- Keep Shop mechanics undefined until the product owner specifies them.
- Do not claim voice, music, haptics, particles, all-platform support, cloud sync or measured 60 FPS until integrated and backed by evidence.
- A green CI build is not a substitute for testing actual source flows and installing the APK on a physical device.
- Add regression tests with backend policy changes, migration/recovery tests with schema changes, and update the roadmap only when acceptance evidence changes.

## 📖 Project documentation

- [Roadmap and progress dashboard](docs/ROADMAP.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Product vision](docs/PRODUCT_VISION.md)
- [Dart backend foundation](docs/DART_BACKEND_FOUNDATION.md)
- [Local-first data foundation](docs/DATA_FOUNDATION.md)
- [Extension repository contract](docs/EXTENSION_REPOSITORIES.md)
- [Decision log](docs/DECISIONS.md)

---

**North star:** a beautiful, genuinely native, storage-conscious comic reader with a living Galaxy, a trustworthy multi-source ecosystem, and immersive features that enhance reading without ever getting in its way.
