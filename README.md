# KuroToon 🌌

**A live-first, cross-source comic reader built around a genuinely great reading experience.**

KuroToon aims to bring webcomics, manga, manhua, creator discovery, a personal library, community source extensions, and an immersive reading experience into one polished product. It should support the web/PWA and a credible Android path without pretending Android-only extensions can automatically run inside a browser.

> **Project status: foundation stage.** This repository began with an initial README only. The documents below describe the product direction; they are not evidence that the features have been implemented. Status will be updated only after code and tests verify it.

## Product principles

- **Reading comes first.** Fast, comfortable, beautiful reading is the product's centre of gravity.
- **One catalog, many sources.** Search across providers and reconcile duplicates carefully without silently mixing editions or translations.
- **Live-first, storage-conscious.** Stream by default, cache intentionally, expose storage controls, and respect the user's limits.
- **Platform honesty.** Browser, PWA, and Android have different capabilities. Test those differences instead of hiding them.
- **Extensions with boundaries.** Reuse community ecosystems where technically and legally feasible; do not assume Android APK extensions are browser-compatible or safe to execute.
- **Preserve user state.** Reading progress and library organization should survive source changes wherever a reliable identity match is possible.
- **Accessible and responsive.** Design for phones first without neglecting tablets and desktop.
- **No fake completion.** Planned, in-progress, implemented, and verified are distinct statuses.

## Core navigation

1. **Home** — continue reading, new chapters, discovery, and personalized collections.
2. **Browser** — unified search, filters, series pages, creator pages, and source discovery.
3. **Shop** — reserved for the reward system; mechanics are intentionally unspecified until the product owner defines them.
4. **Library** — saved series, progress, reading history, categories, sorting, and update tracking.
5. **Me** — profile, settings, storage, privacy, repositories/extensions, audio/reader preferences, backups, and diagnostics.

Reader controls belong inside the reading experience. Settings and extension management should not crowd the main navigation.

## Planned signature experience

- Classic and more immersive reading modes, with motion and effects always controllable.
- Optional music, ambience, sound effects, and spoken dialogue/narration, with separate volume controls and safe defaults.
- A synchronized reading timeline for panel/bubble sequencing, audio cues, and optional auto-scroll.
- A pluggable voice layer with stable character voice identity, pronunciation controls, and user corrections that persist.
- A canonical catalog that distinguishes a work from its editions, translations, provider listings, and chapters.
- Creator/artist pages, careful duplicate grouping, and special handling for specials, mini-chapters, seasons, and doujin organization.

These remain planned until individually implemented and tested.

## Documentation

- [Product vision and scope](docs/PRODUCT_VISION.md)
- [Roadmap and verification gates](docs/ROADMAP.md)
- [Architecture proposal](docs/ARCHITECTURE.md)
- [Decision log](docs/DECISIONS.md)

## First engineering milestone

1. Choose and document the UI/runtime stack after a short feasibility check.
2. Build the responsive shell with the five agreed destinations and a reader route.
3. Define provider, catalog identity, chapter, progress, and storage interfaces.
4. Test one real source end-to-end.
5. Run an Android extension-compatibility spike before promising Mihon/Tachiyomi APK support.
6. Add automated checks and reproducible build instructions.

## Status vocabulary

- **Planned** — agreed direction, not implemented.
- **In progress** — active work exists in the repository.
- **Implemented** — code exists for the stated scope.
- **Verified** — relevant automated/manual acceptance checks passed.
- **Blocked** — a dependency, platform limitation, permission, or unresolved decision prevents progress.

See the roadmap for acceptance criteria.