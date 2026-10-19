# Kurotoon 🌌

> **[⬇️ Native Android preview & build downloads](https://github.com/gtxnrg-ship-it/Kurotoon/actions/workflows/native-android.yml)** · [Legacy prototype APK releases](https://github.com/gtxnrg-ship-it/Kurotoon/releases) · [Legacy prototype build runs](https://github.com/gtxnrg-ship-it/Kurotoon/actions/workflows/android-apk.yml)

**How to download:** open the latest successful **Native Android Preview** workflow run and download the artifact named **Kurotoon-Native-Preview**. The artifact is created only when native tests and APK assembly pass. Until that build turns green, the Releases link above contains the existing experimental Capacitor prototype—not the intended final native app.

**Important:** KuroToon is moving toward a native Kotlin + Jetpack Compose Android architecture. See [Native Android Migration](docs/NATIVE_ANDROID_MIGRATION.md). Do not interpret an installable prototype APK as proof of native implementation or release readiness.

**A live-first manga and webcomic reader set inside a living, personal cosmic universe.**

Kurotoon is intended to become a polished, lightweight, cross-source reader for manga, manhwa, manhua, webtoons, and other comics. It should combine a genuinely excellent reading experience, a coherent multi-source catalog, a user-owned library, a carefully bounded extension ecosystem, and optional synchronized audio, voice, and haptic experiences.

This README is the **canonical product handoff**: it records the product owner's direction, constraints, agreed design principles, implementation priorities, and what is actually built. Treat the vision as requirements for future work—not as evidence that planned features already exist.

> **Current status:** the current main branch is a React + TypeScript + Vite prototype packaged with Capacitor. It contains the five primary destinations, typed catalog/provider contracts, conservative identity matching, a procedural cosmic canvas, live MangaDex search, metadata-only repository management, an in-app series/chapter/page reader, local per-chapter progress, and a CI-generated debug APK. Automated build/test and APK workflows have passed on recent changes, but this is not a native Android implementation. Physical-device acceptance remains pending. Durable Library operations, executable extension runtime, and synchronized audio/voice/haptics are not implemented. The agreed direction is to build a native Kotlin + Jetpack Compose app and migrate capabilities incrementally without losing the current prototype's visual/product work.

## The product in one sentence

Make Kurotoon feel like opening a window into an endless, evolving universe—and then make reading comics through it so fast, comfortable, reliable, and personal that the atmosphere never gets in the way of the story.

## Product principles

1. **Reading comes first.** The reader must remain clear, responsive, comfortable, and dependable even when every immersive feature is disabled.
2. **A living cosmos, not a wallpaper.** The universe should feel continuous, layered, coherent, and gently evolving—not like a static image or random blue particles.
3. **Rich feeling, low resource use.** Achieve depth through procedural graphics, layered parallax, efficient particles, and carefully selected effects before adding large assets or expensive dependencies.
4. **Live-first and storage-conscious.** Prefer live fetching and small bounded caches. Never silently accumulate gigabytes of pages, audio, or artwork.
5. **One catalog, many sources.** Group works intelligently while preserving editions, translations, provider listings, and source provenance.
6. **Immersion is opt-in and cohesive.** Sound, voice, music, motion, and haptics should share a common timeline and settings model rather than behave as unrelated gimmicks.
7. **Graceful degradation.** Core reading must work without audio, voice, haptics, advanced graphics, network access to optional providers, or high-end hardware.
8. **No fake completion.** Planned, in progress, implemented, and verified are different statuses.
9. **Build in small, verifiable increments.** Prefer focused branches and pull requests, test each layer, and keep the README and roadmap synchronized with reality.

## Product boundaries and names

Kurotoon is the manga/webcomic reader. Kurochan is a separate general-purpose app builder. Kuro Canvas is a separate manga-creation studio. Do not merge their roadmaps, branding, assets, or feature assumptions.

The repository is currently named `Kurotoon`. Do not rename the GitHub repository or alter its public identity without explicit authorization.

## Primary navigation

Keep these five destinations in this order:

1. **Home** — continue reading, recent activity, new chapters, and thoughtful discovery.
2. **Browser** — unified search, filters, source discovery, series pages, and creator/artist pages.
3. **Shop** — reserved for a future reward system. Its mechanics are intentionally unspecified; do not invent currencies, prices, streaks, tasks, purchases, or rewards.
4. **Library** — saved series, progress, history, categories, sorting, and update tracking.
5. **Me** — profile and settings, storage controls, privacy, repositories/extensions, reader modes, audio/voice/haptic preferences, backups, and diagnostics.

The reader is its own focused route, not a sixth bottom-navigation item. Source and repository management belongs under **Me → Settings**, not in the main navigation. Do not clutter the bottom bar with plugins or technical controls.

## Signature experience: a living cosmic universe

The environment is one of Kurotoon's defining features. It must feel like a vast, continuous universe that the user is moving through—not a generic gradient with a particle overlay.

### Visual language

- Deep navy, midnight blue, blue, and cyan are the dominant colors, supported by carefully balanced violet.
- Other colors—such as pink, amber, or green—may appear in restrained, astrophysically plausible formations. Avoid unrelated blocks of color or a palette that feels randomly assembled.
- Include multiple kinds of cosmic structure: immense nebulae and gas clouds, translucent gas bubbles, gas giants and planetary silhouettes, star fields with varied sizes and brightness, distant galaxies, dense clusters, sparse voids, and large-scale cosmic filaments.
- Create depth with overlapping layers, scale variation, parallax, atmospheric scattering-like gradients, subtle glow, and slow movement.
- Different regions of the universe may have distinct density and formations, but they must still belong to the same art direction.
- The cosmos should feel expansive and effectively endless. It may evolve continuously, but must not become visually chaotic or compete with text and comic artwork.
- Each installation/session may have a stable procedural seed so users can have subtly different cosmic layouts without downloading a giant background or requiring server-side image generation. The result must remain coherent and reproducible rather than changing arbitrarily on every render.

### Motion and touch

- Use a coherent, shared motion system for ambient drift, parallax, transitions, and touch response.
- Swipes and touches may bend the apparent space field, gently redirect particles, create flowing trails, or trigger subtle light ripples. Gravity/space-bending should be the underlying feel; fluid particle motion and occasional trails are supporting details, not the whole environment.
- Respond to touch direction and speed without interfering with scrolling, taps, page turns, or reader gestures.
- Keep ambient movement slow and comfortable. Respect reduced-motion settings and provide controls for motion intensity.
- Use one shared animation/rendering engine rather than separate uncoordinated effects across screens.
- The first launch may reveal the cosmos in a deliberate sequence—universe, logo, then interface—while later launches should use a shorter, graceful transition. The experience should feel special without making every app opening slow.
- Do not assume a particular mascot or character belongs to Kurotoon. Any character/mascot integration requires a confirmed product decision and the correct project assets.

### Performance requirements

Kurotoon must remain lightweight, especially on lower-end Android phones.

- Prefer procedural rendering, CSS effects, Canvas/WebGL only where justified, and compact shaders over large pre-rendered background files.
- Adapt quality to device capability and observed performance: particle count, blur, glow, update rate, and layered effects can scale down while preserving the art direction.
- Pause or substantially reduce rendering when the tab/app is hidden or the device is idle.
- Avoid unbounded animation loops, memory leaks, expensive per-frame React updates, and main-thread work that stalls navigation or reading.
- Lazy-load nonessential assets and code. Avoid heavyweight libraries unless a measured need justifies them.
- Respect battery saver and reduced-motion preferences; offer manual quality controls as well.
- Keep cosmic visuals subdued behind comic pages and reading text.
- Establish a performance baseline and test on real low-end and mid-range Android hardware before promising specific frame rates or battery impact.

## UI and interaction design

The visual language should feel premium, tactile, and atmospheric without sacrificing readability or consistency.

- Use **glossy/gel-like buttons** for selected primary actions.
- Use **Liquid Glass-style surfaces** selectively for floating controls and transient overlays.
- Use **frosted-glass panels** for layers that need separation from the cosmos, maintaining sufficient contrast behind text.
- Use restrained cyan edge lighting for focus, selected, or active states.
- Use solid, high-contrast surfaces whenever glass or blur would reduce legibility or performance.
- Do not apply blur, glow, gradients, and glass to every element. Avoid visual noise, muddy contrast, and excessive motion.
- Define reusable design tokens for colors, spacing, typography, radii, surfaces, elevation, motion, focus, and responsive breakpoints.
- Keep touch targets generous, keyboard/focus behaviour usable, and layouts responsive across mobile, tablet, and desktop.
- Preserve existing approved assets and visual choices. Do not replace user-provided icons or assets with random/generated placeholders.
- Include truthful loading, empty, partial-result, offline, error, retry, and unsupported-capability states. Never show fake catalog results or pretend a setting is wired when it is not.

## Reader experience and modes

The reader is the core product surface. It needs reliable image loading, bounded preloading, fast chapter navigation, progress restoration, adjustable layout, clear gestures, and recovery from missing or failed pages.

Proposed modes (labels can be revisited, but the distinction should remain):

- **Classic** — clean, fast reading; no added cinematic effects unless individually enabled.
- **Atmosphere** — restrained ambience and subtle environmental effects for readers who want a more enveloping mood.
- **Cinematic** — coordinated optional dialogue, narration, music, scene sound effects, visual cues, and haptics when trustworthy timing information exists.

Mode selection is a preset, not a lock-in. Every layer must have independent controls and be disableable. Users should be able to switch modes or mute/pause immediately without losing reading position. Reading must remain fully usable when every extra is off.

### Reader controls and accessibility

- Support the chosen reading layout(s), next/previous chapter, chapter list, page/scroll progress, and reliable resume behaviour.
- Make gestures predictable and avoid conflicts between cosmic touch effects, scrolling, page turns, zooming, and navigation.
- Respect reduced motion, keyboard navigation where applicable, screen readers, readable contrast, and system accessibility settings.
- Keep original comic panels and order intact by default. Any optional transitions or presentation changes must not distort or obscure the artwork.
- Do not put ambient effects over text in a way that reduces legibility.
- A failed image, audio cue, or provider must never trap the user or corrupt progress.

## One cohesive audio, sound, voice, and haptic system

These features should be designed together around a shared **Reader Timeline / Event Model**, not bolted on independently after the reader is complete. They are a long-term differentiator, but the basic reader comes first and must never depend on them.

### Separate media channels

Provide independent controls for:

- music and adaptive soundtrack;
- ambient sound, such as rain, wind, or room/scene atmosphere;
- discrete sound effects;
- spoken dialogue;
- narration and internal monologue;
- optional character voice profiles;
- haptic intensity and haptic event types.

Include a global pause/mute control, predictable volume defaults, an easy way to disable haptics, and clear settings. Sound should not unexpectedly autoplay at high volume. Respect browser autoplay policies, mobile audio focus, app lifecycle, headphones/route changes where supported, and interruptions. No channel should be required for reading.

### Shared timeline and synchronization

Use one event model to coordinate reading position, chapter/page/panel/bubble cues where available, audio playback, voice lines, optional auto-scroll, and haptic patterns. Define cancellation and reset behaviour for chapter changes, navigation, pausing, seeking, and failed media.

Examples of intended behaviour:
- An impact panel can trigger a brief sound and a short, restrained haptic pulse.
- An energy attack can use a rising electrical sound followed by a sharper pulse.
- A quiet rain scene may use gentle ambience with no constant vibration.
- An emotional moment may use quiet music and no intrusive rumble.
- A monster roar may combine a roar with an optional low-frequency-style haptic pattern if the device supports useful vibration feedback.

These are illustrative design goals, not automatic behaviours that are already implemented. Never vibrate continuously just because the reader is scrolling, and never play a sound for every panel by default.

### Timing truthfulness

Most existing static webcomics do not provide reliable panel-level audio timing. Do not claim perfect automatic synchronization when the source has no timing metadata.

Preferred progression:
1. Support explicit, creator-authored or user-authored cue timelines where available.
2. Add a robust timeline/event schema and a manual correction path.
3. Explore AI-assisted scene/panel analysis that proposes cues with confidence indicators and user approval.
4. Only trigger automatic effects when confidence and user settings permit; allow users to correct or disable them.

When cue data is absent or uncertain, remain silent or use non-specific ambience only when the user has enabled it. Do not invent dialogue, speaker identity, emotions, or event timing as facts.

### Haptic design

- Haptics are optional, capability-aware, and restrained.
- Use short, meaningful patterns for deliberate events such as a confirmed impact or a successful interaction—not for every scroll, touch, particle, or animation.
- Provide intensity/event controls and graceful fallback when vibration is unsupported or restricted.
- Keep haptic timing coordinated with the shared timeline and associated audio.
- Respect device/browser limitations; do not promise identical feedback across hardware.

### Voice and universal dubbing

The long-term voice layer may identify dialogue, narration, internal monologue, and sound-effect lettering; associate text with speakers; and play lines using stable character voice identities. It should support pronunciation dictionaries, corrections, voice-provider alternatives, and a local/device fallback where feasible.

Hard requirements:
- OCR, bubble order, speaker attribution, emotion, timing, and voice selection are inferences with uncertainty—not ground truth.
- Stylized sound-effect lettering such as “BOOM!” is not spoken dialogue by default.
- Show confidence and allow users to correct text, speaker, pronunciation, timing, and voice.
- Preserve user-approved corrections where appropriate and provide a way to review/reset them.
- Avoid silently changing a character's voice identity between chapters.
- Make external speech/AI processing transparent and opt-in where appropriate; minimize data sent and retained.
- Cancel queued voice/audio work when the reader changes chapter or the user disables it.
- Voice generation must not block the basic reading flow.

### Music discovery

A later browser-native music discovery feature may inspect publicly exposed playable audio URLs and source/page/plugin metadata, then associate valid audio with a series, volume, chapter, or relevant media item. It must validate media types, respect source rules, and fall back gracefully to a normal player.

Never bypass DRM, authentication, paywalls, access controls, or private media. Do not assume every page contains a usable soundtrack. Keep music discovery distinct from user-provided or licensed soundtrack playback, and provide clear playback controls.

## Multi-source catalog and identity

Kurotoon should make many sources feel like one coherent catalog without destroying meaningful differences.

Conceptual entities:
- **Work** — the underlying story, series, or one-shot.
- **Edition** — a meaningful language, adaptation, release, or version.
- **Provider listing** — a source-specific record and URL.
- **Chapter** — a logical chapter where identity can be established.
- **Chapter listing** — a provider's version of a chapter, with its own URL, language, and availability.
- **Creator** — author/artist identity backed by source-specific evidence.
- **Reading progress** — durable progress mapped to the logical work/edition where possible.

Requirements:
- Preserve the existing MangaDex live-provider path as one provider; extensions/providers must add to the system, not replace or destroy it. It should be disableable through provider settings when the provider architecture supports that.
- Cross-source search should use bounded concurrency, cancellation, timeouts, and honest partial-result states.
- Match records using multiple kinds of evidence, not title alone. Preserve confidence, reasoning, and provenance; make corrections reversible.
- Do not silently merge distinct translations, editions, adaptations, or similarly titled works.
- Keep alternate titles and aliases.
- Creator/artist pages should aggregate relevant versions from available providers while retaining provenance and uncertainty.
- Represent specials, seasons, mini-chapters, and doujin organization carefully. For example, six mini-chapters should not automatically be presented as six ordinary full chapters without context.
- Show which source supplied a chapter or metadata field and distinguish an actual empty result from a source timeout, block, or error.
- Do not fabricate chapter counts, translation status, release dates, or creator identities when sources disagree.

## Repositories, extensions, and providers

The target ecosystem is familiar repository → extension → source management: users can add a repository, browse its extensions, install or enable a source, update it, disable/remove it, and inspect health/errors. Support one-click/deep-link flows where technically available and manual repository URL entry as a fallback.

Important constraints:
- Preserve MangaDex as a native/live provider option; extensions are additive.
- Investigate community ecosystems such as Mihon/Tachiyomi repositories and alternative sources, but do not assume Android APK extensions can run inside a browser or PWA.
- Prove Android host/API compatibility with a real, isolated proof of concept before promising it.
- A browser-compatible provider adapter may be needed even when an Android extension exists.
- Treat community packages and repository metadata as untrusted. Track source URL, provenance, version, update status, capabilities/permissions, and failure reasons.
- Define bounded request budgets, timeouts, cancellation, and rate limits. Avoid infinite retries, excessive traffic, UI freezes, and behaviour that risks provider bans.
- Do not execute arbitrary community code with unrestricted access to user data, secrets, or storage.
- Make unsupported formats and incompatible versions clear; allow disable/remove and useful diagnostics.
- Repository and extension management belongs in Me → Settings, not main navigation.

## Library, persistence, and storage

The library is user-owned and should survive source changes whenever safe identity mapping is possible.

Planned library capabilities:
- reading states such as reading, completed/read, unread, paused, planned, and dropped;
- custom categories and collections;
- automatic and manual sorting;
- reading history and continue-reading;
- chapter update tracking;
- progress restoration across sessions and, when reliable, source URL changes;
- reversible identity corrections and export/backup options.

Keep durable user data separate from disposable media cache:
- **Durable:** library membership, categories, statuses, sort preferences, reading progress, identity corrections, and user-approved media/voice corrections.
- **Disposable:** thumbnails, page responses, temporary search results, generated audio cache, and temporary OCR output.

Use streaming by default and small, bounded caches. Provide understandable cache limits and cleanup. Downloads, if added, must be explicit, cancellable, visible in storage management, and never silently enabled. Clearing media cache must never erase library metadata or reading progress. Do not upload the entire library or reading history to a server by default.

## Home, Browser, Shop, and Me

- **Home:** continue reading, recent chapters, updates, and curated discovery without a noisy endless feed.
- **Browser:** cross-provider search, filters, source/language selection, aliases, grouped results, creator pages, and visible source health.
- **Shop:** placeholder destination only until the product owner specifies mechanics. No invented reward loops or monetization.
- **Library:** the durable personal collection and progress centre.
- **Me:** settings, repositories/extensions, storage, privacy, appearance, performance, reader/audio/voice/haptic controls, diagnostics, and data export.

## Platform strategy and privacy

The initial web UI uses React + TypeScript + Vite. The PWA and Android delivery strategy remains open until real tests establish the best trade-off for extensions, image-heavy reading, audio lifecycle, file/storage permissions, offline access, and accessibility.

A browser cannot directly execute Android APK extensions. Keep platform-specific capabilities behind explicit interfaces and test platform differences rather than hiding them.

- Core reading should not require account creation or remote synchronization.
- Do not send library history, page content, voice samples, or user corrections to external services without clear disclosure and appropriate consent.
- Keep diagnostics useful but redact secrets, tokens, credentials, and unnecessary personal reading history.
- Avoid unnecessary dependencies; pin dependencies and commit a lockfile as part of reliability hardening.
- Respect source terms, access controls, rate limits, and applicable rights.
- Use real error states and graceful fallback when a provider, speech service, haptic API, or advanced graphics feature is unavailable.

## Chosen implementation order

The product owner has given implementation-order authority to choose the most sensible sequence. The chosen approach is to **build the foundation first**, while shaping it so later immersive features do not require a rewrite.

### Stage 0 — Repository reliability and architecture baseline
- Inspect the actual repository structure and current main branch before editing.
- Keep changes in focused feature branches and PRs.
- Stabilize setup, dependency lockfile/versioning, CI, tests, and documented commands.
- Record mobile performance budgets and platform constraints.
- Keep the README, product vision, roadmap, and decision log truthful and synchronized.

### Stage 1 — Design system and lightweight cosmic engine
- Establish design tokens and accessible interaction primitives.
- Build the procedural, seeded, layered cosmos with adaptive quality and visibility-aware rendering.
- Implement coherent touch/motion handling and responsive app surfaces.
- Add first-launch and subsequent-launch transitions.
- Test low-end Android performance before expanding effects.

### Stage 2 — Real reader and first source
- Complete one end-to-end flow: search → series details → chapter list → page loading → progress save/restore.
- Keep MangaDex available as a provider option, subject to current technical and policy checks.
- Implement bounded preloading, cancellation, error recovery, and source attribution.
- Connect library persistence and truthful empty/loading/partial/error states.

### Stage 3 — Unified catalog and repository research
- Add cross-source search, conservative deduplication, edition/translation distinctions, creator pages, and chapter-structure handling.
- Build repository browsing and provider management.
- Run the Android extension feasibility spike before promising Mihon/Tachiyomi compatibility.
- Add storage controls and persistence/recovery tests.

### Stage 4 — Shared reader timeline and synchronized haptics/audio
- Implement the event/timeline contract and independently controlled audio channels.
- Add haptics as an optional capability and coordinate them with trusted events.
- Support authored cue timelines first; then investigate AI-assisted suggestions.
- Ensure classic reading remains excellent with every effect disabled.

### Stage 5 — Voice, universal dub, and music discovery
- Prototype OCR, dialogue/narration classification, speaker attribution, pronunciation, and stable voice profiles with confidence and correction flows.
- Add provider abstraction, privacy controls, cancellation, and local/device fallback where feasible.
- Add safe public-media discovery and audio association without bypassing access controls.
- Treat these as research-heavy capabilities; do not fake accuracy or block the core reader.

### Stage 6 — Hardening and release readiness
- Test real devices, accessibility, memory, battery, storage, navigation, source failures, audio interruptions, and progress recovery.
- Verify PWA/Android packaging separately.
- Finish backup/export, privacy, diagnostics, dependency security, and release documentation.
- Only mark features verified after their acceptance checks pass.

This order is a plan, not a promise that all stages are complete. Reorder only when implementation evidence or the product owner's priorities justify it, and record meaningful changes.

## Current implementation status

### Implemented / CI-verified
- React + TypeScript + Vite application shell with the five primary destinations: Home, Browser, Shop, Library, and Me. The Library and several settings destinations still need functional integration.
- Dynamic procedural cosmic canvas with layered colour fields, starfield, filaments, touch/pointer ripples, visibility pausing, reduced-motion support, and capped ambient rendering. The cosmic realm is an approved experience and should be preserved; physical-device performance remains to be measured.
- Typed catalog/provider models, conservative work identity matching, source repository index parsing, and the metadata-only repository manager.
- CI build, TypeScript checks, domain tests, and high/critical dependency audit.
- PWA install metadata, bounded app-shell cache, Capacitor Android configuration, a download/install screen, and a GitHub Actions workflow for `Kurotoon.apk`. CI has successfully generated APK artifacts; the APK is a development/debug build, not a production-store signed package.

### Implemented — MangaDex reader path
- Live MangaDex search and source-mapped series metadata.
- In-app series detail page and chapter list, with chapter search and sorting.
- In-app paged and vertical readers, RTL/LTR page navigation, touch/keyboard navigation, safe-area-aware controls, next/previous chapter controls, and series-home return paths.
- Failed-page retry UI and incremental/lazy vertical page mounting; paged preloading is limited to the current page and immediate neighbours.
- Per-chapter reading progress in browser storage with malformed/unavailable-storage handling and vertical restore anchored to the saved page.
- Scroll position measurements are coalesced to animation frames; progress writes are debounced and flushed when the reader is exited or the chapter changes.
- Automated build, tests, and APK packaging have passed on recent reader changes. This does **not** prove the complete live reader flow or sustained 60 FPS on a physical device.

### Remaining / not yet implemented
- Full manual acceptance of search → series details → chapters → page reading, retries, progress restoration, gesture navigation, and three-button Android navigation on a physical device.
- Performance profiling on low-end Android hardware, including sustained frame pacing, memory, battery, background/foreground lifecycle, and graphics interaction. No 60-FPS guarantee is claimed until measured.
- Durable Library functionality: add/remove series, statuses, sorting, collections, history/continue reading, and update tracking.
- Full settings integration and advanced storage/privacy/diagnostics workflows.
- Executable source extensions, source activation/runtime, binary `index.pb` support, trust/signature verification, and proven Android extension compatibility.
- Live comments/reactions backend, spoiler-safe threaded discussion, shared reader audio timeline, synchronized effects, voice/universal dubbing, haptics, and music discovery.
- Account sync, explicit offline downloads, backup/export, and specified Shop/reward mechanics.

The repository manager is a real metadata-only interface: saved HTTPS JSON URLs, add/check/refresh/remove, local browser persistence, error states, and extension-list filtering. Other settings destinations are still scaffolds. This does not install, enable, or execute third-party extensions; browser CORS restrictions can prevent a repository from being checked.

### Android / APK status
- The GitHub Actions workflow has successfully built the installable debug package named **`Kurotoon.apk`** and uploaded workflow artifacts on verified runs. The latest temporary artifact is available from its successful Actions run; the [Releases page](https://github.com/gtxnrg-ship-it/Kurotoon/releases) is the place to check for the latest published continuous development build.
- The APK is a debug/development build, not production-store signed. A successful CI build proves packaging, **not** installation, stability, navigation behaviour, or performance on a physical phone.
- Physical install and low-end Android acceptance remain open release checks.

## Status vocabulary

- **Planned** — agreed direction, not implemented.
- **In progress** — active code or documentation work exists.
- **Implemented** — the stated scope exists in code.
- **Verified** — the relevant automated and/or manual acceptance checks passed.
- **Blocked** — a dependency, platform limitation, permission, or unresolved product decision prevents progress.

## Engineering rules for future work

1. Inspect the actual file tree and current branch before assuming paths or editing.
2. Work through small, reviewable pull requests; do not commit directly to main as the default workflow.
3. Add tests with domain behaviour, especially identity matching, chapter structure, progress, storage, and timeline cancellation.
4. Keep platform, provider, speech, audio, haptic, and rendering capabilities behind explicit interfaces.
5. Bound network concurrency, media preloading, caches, background work, and retries.
6. Do not add dependencies without a concrete need and maintenance assessment.
7. Never commit secrets, tokens, private credentials, or user data.
8. Keep source attribution and uncertainty visible; never fabricate content or claim unsupported compatibility.
9. Update this README and the roadmap when implementation status changes.
10. Preserve the product owner's approved assets, five-destination navigation, low-storage priority, and separation between Kurotoon, Kurochan, and Kuro Canvas.

## Installing and downloading Kurotoon

The web app includes a PWA manifest and a deliberately bounded app-shell cache. Once deployed over HTTPS, use the browser's **Install app** or **Add to Home Screen** command. This only caches the app shell and a limited number of same-origin code assets; it does not bulk-download comic chapters or artwork.

The Android packaging workflow is `.github/workflows/android-apk.yml`. It builds an installable debug APK named **`Kurotoon.apk`**, uploads it as a temporary workflow artifact, and publishes a continuous development release after successful updates to `main`. Version tags beginning with `v` create non-prerelease releases. The first APK must be verified by a successful workflow run before it should be treated as available. Development APKs are not production-store signed.

## Running the foundation UI

Requirements: Node.js 20 or newer and npm.

```sh
npm install
npm run dev
```

Run the production build/check command:

```sh
npm run build
npm run preview
```

Use the repository's current scripts as the source of truth if they change. Commit the lockfile and verify a clean install as part of reliability hardening.

## Documentation

- [Product vision](docs/PRODUCT_VISION.md)
- [Roadmap and acceptance gates](docs/ROADMAP.md)
- [Architecture proposal](docs/ARCHITECTURE.md)
- [Decision log](docs/DECISIONS.md)
