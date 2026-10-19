# KuroToon Roadmap

This is a living plan. Items stay **Planned** until code exists and the acceptance criteria pass. Do not report a whole phase complete because its documents exist.

## Phase 0 — Foundation and feasibility

Status: **In progress** — initial web build and CI are verified; Android feasibility remains open.

- [x] Establish public repository and initial documentation baseline.
- [x] Select the initial web UI stack: React + TypeScript + Vite; keep Android packaging/runtime decision open pending feasibility evidence.
- [x] Define type-check/production-build and unit-test commands.
- [x] Add CI checks for pull requests and main-branch pushes.
- [ ] Document local setup and environment variables; commit no secrets.
- [ ] Record a baseline performance budget for mid-range Android devices.

**Exit gate:** a clean checkout can install dependencies, run checks, and build a minimal responsive shell using documented commands.

## Phase 1 — App shell and design system

Status: **In progress** — the initial procedural cosmic canvas is merged and CI-verified; physical-device performance validation remains pending.

- [ ] Establish responsive dark-first design tokens, typography, spacing, surfaces, motion, focus states, and reduced-motion support.
- [x] Add a first procedural cosmic canvas with layered colour fields, starfield, subtle large-scale filaments, pointer/touch ripples, visibility pausing, and reduced-motion handling (CI-verified; physical-device validation pending).
- [ ] Add adaptive quality settings and validate GPU/memory/battery behaviour on low-end Android hardware.
- [ ] Implement persistent five-destination navigation: Home, Browser, Shop, Library, Me.
- [ ] Add empty, loading, error, offline, and retry states.
- [ ] Add reader route and shared app-level settings boundary.
- [ ] Verify narrow mobile, tablet, and desktop layouts.
- [ ] Add a first-launch cosmic reveal and shorter subsequent-launch transition only after the base renderer is profiled.
- [ ] Keep source/repository management under Me/settings.

**Exit gate:** navigation is keyboard/touch usable, responsive, and does not lose route state during ordinary navigation.

## Phase 2 — Domain model and provider boundary

Status: **In progress**

- [x] Define typed models for Work, Edition, ProviderListing, Chapter, ChapterListing, Creator references, ReadingProgress, LibraryEntry, and ProviderHealth.
- [x] Define source adapter contract for search, details, chapter list, and page retrieval.
- [x] Define provider capability flags, cancellation signals, and structured provider errors; request budgets/timeouts still need enforcement.
- [x] Add conservative work identity matching with confidence, reasons, and an explicit auto-merge threshold; persistence/provenance UI remains.
- [ ] Expand domain tests to cover editions, mini-chapters, specials, progress remapping, and provider failures (initial identity tests exist).

**Exit gate:** domain logic can be tested without UI or a live provider, and source failures are distinguishable from empty results.

## Phase 3 — First real source and core reader

Status: **In progress** — a MangaDex adapter and live Browser search are being implemented on a feature branch; CI is pending. Built-in chapter reading is not complete.

- [x] Add a typed MangaDex search adapter with cancellation, timeout, explicit provider failures, and a conservative content-rating default (feature branch; pending CI).
- [x] Render real MangaDex search results with source attribution and honest loading/empty/error states (feature branch; pending CI).
- [ ] Prove the complete in-app flow: search → series details → chapter list → page retrieval.
- [ ] Build image preloading with cancellation and bounded concurrency.
- [ ] Save and restore reading position reliably.
- [ ] Support next/previous chapter and recover from missing pages.
- [ ] Add library add/remove/status/sort and progress persistence.
- [ ] Make source health and attribution visible.

**Exit gate:** a reader can find a series, read a chapter, leave, return, and resume at the expected location; tests cover source failure and progress recovery.

## Phase 4 — Repository and extension research gate

Status: **Planned; high-risk feasibility item**

- [ ] Parse a real community repository index without installing anything.
- [ ] Inspect package formats, host API versions, dependencies, signatures, and license notices.
- [ ] Build a disposable Android proof of concept for one extension, if licensing and technical feasibility permit.
- [ ] Verify search, details, chapters, and page URLs through the host interface.
- [ ] Document what cannot be supported in a browser/PWA.
- [ ] Decide between native compatibility, a restricted adapter bridge, and provider adapters authored for KuroToon.
- [ ] Define source permissions, provenance, update policy, rate limits, and safe failure.

**Exit gate:** a tested architecture decision with evidence. No production promise of generic Mihon/Tachiyomi compatibility before this gate passes.

## Phase 5 — Unified catalog and discovery

Status: **Planned**

- [ ] Cross-provider search with bounded parallel requests and cancellation.
- [ ] Local search index for already-seen metadata.
- [ ] Aliases and alternate titles.
- [ ] High-confidence duplicate grouping with manual correction.
- [ ] Separate works, editions/translations, listings, and chapters.
- [ ] Creator/artist pages with provenance.
- [ ] Explicit handling for specials, mini-chapters, seasons, and doujin structure.
- [ ] Explain partial results when a source is slow, blocked, or offline.

**Exit gate:** test fixtures prove that distinct editions are not incorrectly merged and source timeouts are not shown as “no results.”

## Phase 6 — Immersive reader and audio

Status: **Planned; staged rollout**

- [ ] Define a single reader timeline and event model.
- [ ] Add independently controlled dialogue, narration, music, ambience, and effects.
- [ ] Add safe volume defaults, global pause/mute, audio focus, and no surprise autoplay.
- [ ] Prototype OCR/bubble order/speaker labeling with confidence indicators.
- [ ] Add voice profiles and pronunciation dictionaries.
- [ ] Allow line corrections and persist user-approved corrections.
- [ ] Add optional auto-scroll and tempo controls.
- [ ] Test low-memory and interrupted-network behaviour.

**Exit gate:** basic reading works without audio; audio can be disabled instantly; timeline interruption/restart does not corrupt reading progress.

## Phase 7 — Storage, reliability, and privacy

Status: **Planned**

- [ ] Storage dashboard and cache limits.
- [ ] Separate disposable image/audio cache from durable library/progress data.
- [ ] Cleanup and recovery tests.
- [ ] Data export/backup design.
- [ ] Privacy review for history, analytics, and external speech providers.
- [ ] Diagnostics that redact tokens and personal data.
- [ ] Performance tests on slower mobile hardware.

**Exit gate:** cache cleanup cannot erase the library/progress; network and provider failures remain recoverable.

## Phase 8 — Shop / rewards

Status: **Blocked on product specification**

The destination remains in navigation, but mechanics must wait for the product owner's explanation. Do not implement guessed currency, reward loops, tasks, purchases, or monetization.

## Phase 9 — Release readiness

Status: **Planned**

- [ ] Accessibility and interaction audit.
- [ ] Security and dependency review.
- [ ] Android/PWA install and update tests.
- [ ] Reproducible production build.
- [ ] Clear release notes and known-limitations list.
- [ ] Validate all claims in README against actual behaviour.

## Working rules

1. Prefer small, reviewable pull requests with a clear acceptance gate.
2. Keep Implemented separate from Verified.
3. Add tests with domain behaviour, especially identity/progress/storage logic.
4. Do not add a dependency without a concrete reason and maintenance assessment.
5. Never put secrets, private tokens, or personal credentials in source control.
6. Revisit this roadmap when evidence or the owner's priorities change.