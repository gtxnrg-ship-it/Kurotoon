# KuroToon Multiplatform Architecture

## Product decision

KuroToon is a multiplatform application family, not an Android-only app and not a website wrapped in a native shell. The intended supported platforms are Android phones and tablets, iPhone and iPad, Windows desktop, Linux desktop, with macOS as a reasonable additional target when build and testing pipelines support it.

The same product identity, series/catalog model, source contracts, chapter reconciliation rules, preferences schema, and Galaxy visual language should carry across platforms. Each platform must still feel designed for its device.

## Recommended technology: Flutter first, native adapters where needed

For KuroToon's priorities—highly animated UI, a distinctive GPU-rendered Galaxy atmosphere, Android + iOS + Windows + Linux, and a single carefully tuned UI implementation—the leading recommendation is **Flutter with Dart**, using Flutter's Impeller renderer on supported targets. Flutter has first-party deployment paths for Android, iOS, Windows, Linux and macOS, while Impeller is designed for predictable rendering by compiling shaders ahead of runtime and managing graphics resources explicitly. This is a better initial fit to benchmark for the *whole animated product* than committing to Kotlin/Compose as the universal UI stack.

This is a reasoned architecture recommendation, not a promise that Flutter automatically guarantees smoothness. Every framework can stutter when images, network work, state updates, decoding, audio inference or GPU work are poorly scheduled. We must validate the decision on actual low-end hardware before treating it as settled.

- **UI and interaction:** Flutter/Dart for adaptive screens, navigation, shop interactions, transitions, settings and shared mobile/desktop UI.
- **Rendering:** Impeller where supported; custom shaders and particle rendering only after profiling. Keep the Galaxy renderer isolated so it can be optimized or replaced without rewriting catalog/business logic.
- **Shared domain logic:** Dart packages initially for series identity, catalog merging, source contracts, reading progress and app state. Keep clear interfaces so genuinely CPU-heavy algorithms can later move to Rust only if benchmarks prove it necessary.
- **Platform adapters:** Kotlin/Java for Android-only integrations; Swift/Objective-C for iOS integrations; small native Windows/Linux bridges only when Flutter plugins do not cover a required capability.
- **Voice and audio:** Flutter-facing service interface, platform audio/session adapters, and optional model runtime chosen only after testing memory use, startup latency, licenses and support on each target.
- **Distribution:** Flutter build/release jobs per OS. iOS builds require macOS and Xcode; desktop release formats are platform-specific.

Do not use a WebView or wrap the existing website as the primary app. The app should use Flutter's native application runtime and platform integrations. Do not assume a plugin works on every OS just because it works on Android; check and test each target.

## Proposed repository structure

```text
native-android/              # Existing Android-only experiment; temporary migration track
shared/
  core-models/               # Work, edition, chapter, creator, provider, progress models
  catalog/                   # Identity, deduplication, reconciliation, provenance
  source-api/                # Stable provider contract, capabilities, permissions
  source-runtime/            # Constrained source execution boundary
  networking/                # Bounded HTTP, retries, timeouts, cancellation, rate limits
  storage/                   # Shared repositories/interfaces and portable migrations
  sync/                      # Optional sync protocol; local-first remains usable without it
  experience/                # Platform-neutral settings and interaction contracts
  galaxy/                    # Shared palette, motion parameters, particle definitions
composeApp/                  # Shared adaptive Compose UI and navigation
androidApp/                  # Android entry point and platform adapters
iosApp/                      # Xcode project, iOS entry point and platform adapters
desktopApp/                  # Windows/Linux/macOS entry point and packaging
.github/workflows/           # Per-target build, test, artifact and release workflows
docs/
  MULTIPLATFORM_ARCHITECTURE.md
```

This is a target layout, not a claim that all modules already exist. Move code into modules only after each boundary has a testable contract; avoid empty modules created only to make the tree look complete.

## Shared versus platform-specific

### Shared
- Canonical series identity and duplicate detection with confidence scores.
- Provider/source contracts, listing provenance and provider capability declarations.
- Chapter identity and reconciliation across translations, editions and mini-chapters.
- Library and progress domain models; import/export format.
- Request scheduling policies, cancellation contracts and rate-limit rules.
- Galaxy design tokens, particle descriptions, motion settings and UI state.
- Validation, migration rules and domain-level tests.

### Platform adapters
- UI lifecycle, file picker, share sheet, permissions, notifications and background work.
- Secure storage, database driver, image decoding and cache implementation where target constraints differ.
- TTS engine, optional neural voice runtime, audio focus/session, haptic hardware and controller support.
- Installation, updates, packaging and signing.

## Galaxy atmosphere

The Galaxy effect is an interactive rendering system, not a pre-rendered animated wallpaper. Share the parameters and behaviour, not necessarily one identical renderer:
- Slow multi-hue nebula drift and gradual palette transitions.
- Layered stars, subtle filaments, occasional shooting stars and restrained interaction ripples.
- Deterministic seeds and bounded particle counts to avoid runaway memory or frame-time cost.
- Frame-rate-aware animation, lifecycle pause, battery-aware intensity and reduced-motion support.
- Optional motion intensity setting and an accessible static fallback.
- Keep reader pages visually calm; particle density and brightness must not interfere with comic readability.

Each platform can use a renderer optimized for its GPU and lifecycle while following the same visual specification and tests.



## Performance contract: smoothness is a release gate

“Runs on the device” is not enough. The target is consistently responsive across the entire app, not just the reader.

- **Frame budget:** target 60 fps on the agreed low-end reference devices, with p95 frame times within 16.7 ms for scrolling, transitions, shop micro-animations and the Galaxy background. Higher-refresh devices should use their available refresh rate where practical; the 90/120 Hz budgets are tighter (11.1/8.3 ms).
- **Jank testing:** record missed frames and p50/p95/p99 frame times in profile/release builds, not debug-only builds. Test long catalog lists, fast scroll + image loading, shop transitions, tab switching, search typing, downloads, and particle effects together.
- **No main-thread blocking:** network calls, image decoding, database work, parsing, archive operations and model loading must never block UI interaction. Use cancellation, bounded concurrency and incremental results.
- **Adaptive quality:** dynamically reduce particle density, blur resolution, glow layers and background update rate when frame times or thermal pressure rise. Respect reduced-motion settings and battery saver. Never let decorative effects starve taps or scrolling.
- **Images and cache:** virtualized lists, thumbnail sizes, progressive image loading, decode limits, memory-aware cache eviction and no unbounded prefetch.
- **Voice packs:** optional downloads with checksums, resumable transfers and storage caps. Keep neural inference off the UI isolate/thread, use quantized models where suitable, load models on demand, and release memory when voice is inactive. A voice pack must not make browsing or animations hitch.
- **Particles and transitions:** use bounded particle counts, deterministic seeds, reusable buffers and GPU-friendly batching; avoid per-frame allocations and rebuilds of unrelated UI. Animation work must pause when not visible.
- **Release gate:** no platform is marked supported until the performance test suite passes on a documented low-end device and representative desktop/mobile hardware. If a target misses the gate, optimize or lower effect quality gracefully rather than claiming flawless performance.

Framework choice gives us a strong starting point; profiling, budgets and hardware testing are what protect the feel over time.

## Source ecosystem and safety boundaries

The source API must be versioned and platform-neutral. A provider advertises capabilities (search, metadata, chapter list, page resolution, updates), supported languages, attribution and permission requirements. Network concurrency, retries, cancellation, parsing size and per-provider timeouts are enforced by the host.

Do not blindly execute downloaded code from community repositories. Prefer declarative manifests plus a constrained provider runtime. If executable extensions are eventually supported, define a permission model, signature/checksum verification, version compatibility, isolation strategy, user consent and revocation mechanism first. Mihon/Tachiyomi extension compatibility must be proven independently; it is not assumed.

## Local-first data and cross-device continuity

- Reading must work without an account.
- Library and reading progress remain user-owned data, separate from temporary provider observations and image caches.
- Users can export and import library/progress in a documented versioned format.
- Optional cross-device sync can be added later; never make it mandatory to browse or read.
- If sync is added, encrypt transport, minimize stored data, make sync opt-in, resolve conflicts deterministically, and provide deletion/export controls.
- Never silently upload reading history, voice recordings or private preferences.

## Audio, voice and haptics

Define common interfaces and platform adapters. Basic system TTS is a fallback, not the same as a bundled neural voice. Neural voice packs must be optional downloads with license and attribution metadata, platform/ABI compatibility, verified checksums, bounded storage, cancellation/resume, explicit user activation and clear deletion controls. No audio should autoplay. Haptics degrade gracefully when unsupported or disabled.

## CI and release strategy

Create independent workflows for:
1. Shared Kotlin unit tests and static checks.
2. Android APK build and tests.
3. iOS build/test on a macOS runner; publish signed artifacts only when signing secrets and Apple provisioning are configured.
4. Windows and Linux desktop build/test and platform-specific packages.
5. Optional macOS desktop build/test.
6. Cross-platform contract tests for catalog identity, chapter reconciliation, source cancellation, progress migration and Galaxy motion settings.

A green Android build does not prove the iOS or desktop app builds. Show separate status for each target and never advertise a platform download until its workflow has successfully built and tested that target.

## Migration order

1. Keep the current prototype and Android experiment as references; do not delete working work prematurely.
2. Establish Dart package boundaries and platform-neutral catalog/source contracts, with tests before migration.
3. Build the Flutter app shell and port the native Android experiment's validated features into shared Flutter/Dart packages; keep native adapters for hardware APIs.
4. Build and validate the iOS/iPadOS target with Xcode on macOS, including voice, audio, haptics and lifecycle adapters.
5. Build and validate Windows and Linux desktop targets, keyboard/resizable-layout behaviour and packaging.
6. Port the reader as a shared feature with platform-specific file/audio/gesture integration.
7. Integrate optional voice packs and richer haptics only after runtime compatibility and licensing checks.
8. Test real devices and desktop environments, accessibility, offline mode, memory use and low-end hardware.

## Definition of done

A platform is supported only when its target builds from a clean checkout, automated tests pass, the app installs and launches, core navigation works, search → series → chapter → reading progress works end-to-end, data export/import is tested, and the Galaxy renderer respects reduced motion. Shared code existing alone does not qualify as platform support.
