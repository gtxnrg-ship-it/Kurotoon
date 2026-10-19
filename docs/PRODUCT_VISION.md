# KuroToon Product Vision

## North star

Make reading comics from multiple sources feel like using one coherent, premium library—not a collection of unrelated scrapers. The app should feel calm and fast for ordinary reading, then become richly atmospheric when the reader explicitly enables cinematic features.

## Who it serves

- Readers who follow series across different publishers, sources, and translations.
- Readers who want their library and progress to remain useful when a source changes or disappears.
- Readers who prefer streaming and low device storage but still want explicit offline options.
- Readers who want optional audio, voice, and motion without being forced into them.

## Experience pillars

### 1. Reader quality

The reader is the most important surface. It needs reliable image loading, fast chapter navigation, gestures that do not conflict, precise progress restoration, adjustable layout, accessibility options, and graceful recovery from broken pages.

Potential modes are working labels, not final names:
- **Classic:** predictable, lightweight reading.
- **Atmosphere:** optional ambience and restrained effects.
- **Cinematic:** coordinated dialogue, narration, sound cues, and reading progression.

Every effect must be optional. Audio should never start unexpectedly at a high volume. Music, dialogue, narration, ambience, and effects should be independently adjustable. A global pause/mute must be easy to reach.

### 2. Optional universal dub

The long-term concept is an audio layer that can identify dialogue, narration, internal monologue, and sound-effect lettering; associate lines with speakers; preserve each character's voice identity; and synchronize playback with reading progression.

The architecture must allow multiple speech providers and a device/local fallback where feasible. OCR, bubble order, speaker attribution, emotion, timing, and voice selection are uncertain inference steps—not facts. Users must be able to correct them, inspect the result, and keep their corrections. Stylized lettering such as “BOOM!” must not be treated as spoken dialogue by default.

This is a major research and implementation track, not a baseline promise. The initial reader must work perfectly without it.

### 3. One catalog across sources

A single story may appear under different titles, languages, scanlation groups, editions, seasons, and provider URLs. KuroToon should model these separately:
- **Work:** the underlying series or one-shot.
- **Edition:** a meaningful release/version, including language or adaptation.
- **Provider listing:** a source-specific record and URL.
- **Chapter:** a stable logical chapter identity where confidence supports it.
- **Chapter listing:** the provider's version of that chapter, with its own URL, language, and availability.

Only merge records when evidence supports it. Low-confidence matches should be presented as possible duplicates, not silently merged. Users need a way to undo or correct a match. Preserve provenance and show which source supplied each detail.

Specials, mini-chapters, season breaks, alternate editions, and doujin chapter structures must not be flattened into a misleading count. A series with six mini-chapters should not be reported as six ordinary full chapters without context.

### 4. Extension ecosystem

The goal is a repository → extension → source workflow familiar to users of extension-based comic readers, with repository URLs, repository browsing, source installation/enable-disable, updates, health reporting, and manual repository entry.

Compatibility is a technical gate, not an assumption: Mihon/Tachiyomi extensions are commonly Android packages tied to their host APIs. A browser cannot execute those APKs directly. Investigate a real Android compatibility proof of concept before selecting the production approach. Do not execute arbitrary community code with unrestricted privileges. Track source provenance, version, permissions/capabilities, update status, and failure reasons.

### 5. Live-first, low-storage operation

Default to streaming and small, bounded caches. Make cache size and cleanup understandable. If chapter downloads are later supported, they must be explicit, cancellable, and visible in storage management. Cache eviction must never delete the user's library metadata or reading progress.

### 6. User-owned library

The library should support read, unread, reading, paused, planned, and dropped states; custom categories; automatic and manual sorting; update tracking; history; and stable progress. It should preserve user organization even when provider listings are removed or remapped.

### 7. Discovery and creators

Home should make it easy to continue reading and find new work without turning into an endless noisy feed. Browser should provide cross-source search and filters, grouped results, aliases/alternate titles, language and source filters, and clear source-health status. Creator pages should aggregate works across sources while retaining evidence and alternate identities where appropriate.

### 8. Shop / reward system

The Shop destination is reserved, but its mechanics are **not defined yet**. Do not invent currencies, tasks, prices, streaks, monetization, or rewards. Keep it isolated behind a feature boundary until the product owner provides the rules.

## Primary navigation contract

Home · Browser · Shop · Library · Me

This order should remain stable unless the product owner explicitly changes it. Settings and source management belong under Me/settings rather than as extra permanent bottom-nav items.

## Non-goals for the first milestone

- Implementing every provider before the architecture is proven.
- Promising universal APK extension compatibility before a working test.
- Requiring AI/audio for normal reading.
- Uploading the user's entire library or reading history to a server by default.
- Inventing content metadata when sources disagree or time out.
- Building Shop mechanics before they are specified.

## Quality bar

Judge the product on correctness and feel, not feature-count alone: no lost progress, no UI freezes during source work, honest loading/error states, stable navigation, clear source attribution, accessible controls, and graceful behaviour on slower phones.