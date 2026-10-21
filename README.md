> **[⬇️ Download the latest Android APK](https://github.com/gtxnrg-ship-it/Kurotoon/releases/download/continuous-latest/Kurotoon.apk)** · [All releases](https://github.com/gtxnrg-ship-it/Kurotoon/releases) · [Build history](https://github.com/gtxnrg-ship-it/Kurotoon/actions/workflows/android-apk.yml)

# KuroToon 🌌

**KuroToon is being built as a native Flutter/Dart app—not a website wrapped in Capacitor.** The default download is an `arm64-v8a` APK to avoid bundling unused CPU architectures. Older 32-bit ARM devices can use `Kurotoon-armeabi-v7a.apk`; x86-64 builds and SHA-256 checksums are included on the [latest release](https://github.com/gtxnrg-ship-it/Kurotoon/releases/tag/continuous-latest). This is a development build; install and test it on your device before relying on it.

A live-first manga, manhwa, manhua and webtoon reader set inside a living, evolving cosmic universe. The goal is a lightweight, polished reading app with a unified multi-source catalog, a durable user-owned library, safe repositories/extensions, and optional synchronized voice, audio, music and haptics.

---

## 🚦 Project dashboard

**Last roadmap checkpoint:** 19 October 2026  
**Overall product estimate:** **~43%**  
**Backend foundation estimate:** **~66–68%**

These are engineering estimates based on the roadmap and implementation evidence—not code-line counts, automated coverage, or a claim that the product is almost finished. Backend models and safety policies count as foundation work; a feature is not considered complete until its real app flow is integrated and tested.

| Workstream | Estimate | What exists today | Main remaining gate |
|---|---:|---|---|
| Native build and CI | 90% | Flutter/Dart app, analysis/tests, release APK workflow | Physical-device install, smoke tests, release/signing policy |
| Dart domain and policy core | 70% | Typed catalog/provider models, identity matching, cancellation, progress and effect/voice policies | More adversarial tests and full end-to-end consumers |
| Persistence and cache safety | 65% | SQLite schema/migrations, enforced cache budgets, pinned-content protection, rollback tests, persisted provider-health snapshots and verified voice-pack install records | Verify complete CRUD integration, crash recovery and physical-device storage behaviour |
| Providers | 58% | Native MangaDex adapter, bounded coordination, persistent failure streaks/cooldowns and upstream `Retry-After` handling | Device verification, provider-specific policies, diagnostics UI and more adapters |
| Repository/extension foundation | 65% | Repository/manifest validation, preview-before-add, hash/size checks, persistent records | Full repository UI, install/update/remove recovery and compatibility proof |
| Cross-source catalog | 45% | Work/edition/listing concepts, conservative matching and grouping policies | Persisted merge pipeline, undo/corrections, artist pages and real fixtures |
| Native reader and library | 20% | Domain/persistence foundation and earlier prototype evidence | Flutter-native chapter reader, page loading, progress resume, full library UI |
| Galaxy and adaptive performance | 25% | Initial animated native shell and effect-budget policy | Lifecycle/reduced-motion hardening and real device profiling |
| Voice, music, haptics and particle runtime | 18% | Reader-timeline/policy foundation plus verified voice-pack storage, offline reuse and safe uninstall | Voice-pack UI/playback, music discovery, native haptics, particle controls and device tests |
| Other platform releases | 10% | Shared Dart core intended to be portable | iOS/iPadOS/Windows/Linux host integration and validation |

**How to read this:** the foundation is ahead of the end-user experience. A green CI run proves that the tested code builds and its automated tests pass; it does not prove real-source reliability, phone performance, or complete feature wiring.

For the detailed acceptance checklist, see the [Roadmap](docs/ROADMAP.md).

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

The repository manager can discover the compatible starter index from this repository URL or README: [KuroToon Official Starter Repository](catalog/official/index.json). This starter currently provides metadata search only; it is not a chapter-reading source.

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

The backend foundation includes typed domain contracts, provider coordination, conservative identity matching, SQLite persistence/migrations, repository/manifest validation and policy models. Managed cache writes enforce the shared byte budget, serialize concurrent writes, protect pinned entries, stage evictions/replacements and roll back file changes if SQLite rejects the metadata commit. Provider health now tracks failure streaks, uses bounded cooldowns, respects upstream `Retry-After`, and persists validated snapshots locally without saving raw provider error text. Remaining integration work includes complete CRUD flows, crash/restart recovery for interrupted cache writes, migration fixtures, a health/diagnostics UI, provider-specific request policies, redacted diagnostic export, and explicit backup/import/export flows.

Downloads must be explicit, cancellable and visible in storage management. Clearing media cache must not erase library or reading progress. Do not silently accumulate gigabytes of comic pages, audio or artwork.

## 🎧 Voice, music, haptics and particles

These features should share a **Reader Timeline / Event Model**, rather than behave like unrelated effects.

- Independent controls for music, ambience, sound effects, dialogue, narration, character voice and haptic intensity.
- Global pause/mute, safe volume defaults, no unexpected autoplay and cancellation on chapter changes.
- Haptics are brief, optional, capability-aware and tied to meaningful user-approved events—not every scroll or particle.
- Voice-pack storage now enforces explicit opt-in, license/size/free-space gates, streamed SHA-256 verification, redirect and non-public-host rejection, content-addressed installation, offline reuse and safe removal. User-visible download progress/cancellation and playback are still pending.
- OCR, bubble order, speaker, emotion and timing are uncertain inferences; show confidence and allow correction.
- Most static comics do not contain trustworthy panel-level timing. Never claim perfect automatic synchronization without suitable cue data.
- Music discovery must respect source rules and access controls. Never bypass DRM, authentication or paywalls.
- All immersive features must be opt-in, independently disableable and irrelevant to the reliability of ordinary reading.

Verified voice-pack file storage is implemented, but that does **not** mean the complete voice runtime, music engine, haptic synchronization or all particle mechanics are wired up. Reader UI/playback, music discovery, haptic adapters and effect controls remain explicit implementation gates.

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

## 📖 Project documentation

- [Roadmap and progress dashboard](docs/ROADMAP.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Product vision](docs/PRODUCT_VISION.md)
- [Decision log](docs/DECISIONS.md)

---

**North star:** a beautiful, genuinely native, storage-conscious comic reader with a living Galaxy, a trustworthy multi-source ecosystem, and immersive features that enhance reading without ever getting in its way.
