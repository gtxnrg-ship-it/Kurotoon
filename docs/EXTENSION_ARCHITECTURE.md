# Kurotoon Universal Source and Catalog Architecture

## Product rule

Kurotoon is a client-side discovery and reading platform, not a comic host and not a MangaDex reskin. Sources retain ownership of their content and URLs. Kurotoon searches sources, presents normalized metadata, and opens chapter content through source adapters. It must not scrape or proxy every page through a Kurotoon server by default.

## Separate concepts (do not collapse these tables)

- **Repository**: a trusted/untrusted catalog location that advertises extension metadata.
- **Extension package**: versioned source integration with an explicit compatibility contract, permissions, origin, signature/hash where available, and update policy.
- **Provider**: a running adapter implementing Kurotoon's stable source API.
- **Provider listing**: a source-specific record and URL. Never delete this when grouping duplicates.
- **Work**: the cross-source identity for an underlying story.
- **Edition**: a language, adaptation, release line, or format variant where it meaningfully differs.
- **Chapter**: a normalized chapter identity within an edition.
- **Chapter listing**: the source-specific chapter ID, URL, language/team, timestamp, and page locator.
- **Library entry / progress**: user-owned data linked to stable work/edition IDs, not provider-specific IDs.

A universal work may contain many provider listings and editions. A chapter number alone is not a global chapter identity: sources split chapters into minis, combine them, rename them, use decimals, omit numbers, or publish separate translations. Never merge chapter pages just because labels look alike.

## Extension compatibility strategy

1. Define and version a Kurotoon-native TypeScript/JSON contract with capability discovery, normalized models, cancellation, bounded requests, health checks, and structured failures.
2. Support static JSON repository indexes as discovery metadata only, with schema validation, size/time limits, safe HTTPS URL rules, and clear trust labels.
3. Keep repository management, extension installation, provider registration, and source execution as separate services. A repository listing is not an installed extension.
4. Do not execute arbitrary downloaded JavaScript in the app's main context. A web extension needs a deliberately sandboxed runtime, permission model, CSP/origin restrictions, message validation, and timeouts. Native Kotlin/APK extensions are not automatically compatible with a browser PWA; compatibility needs a separately implemented bridge or a community port.
5. Make source disable/remove reversible and preserve library, work identities, chapter progress, and source history when an extension disappears.

## Universal search

- Search enabled providers concurrently with a global deadline and per-provider timeout/concurrency limits.
- Return successful results even if another source fails; show partial results and per-source health/error details.
- Deduplicate only exact duplicate listings within the same provider/work key.
- Group likely same works using namespaced external IDs, normalized titles/aliases, creator identity, original language, format/adaptation evidence, and user-confirmed equivalences.
- Do not auto-merge on title alone. Ambiguous candidates become review suggestions.
- Preserve every source listing under the canonical work, including source URL, language, cover, status, and last verification timestamp.
- Canonical title is a presentation choice, not a destructive rename of provider metadata. Keep aliases/search terms and allow user override.
- Index by normalized title/alias and external identifiers. Use blocking/indexes rather than all-pairs comparison for large catalogs. A common-title block must be capped or routed to review; never run unbounded quadratic matching over hundreds of thousands of records.
- A source's latest chapter is not automatically the global latest chapter. Compare compatible edition/language/team releases, publish timestamps when reliable, chapter order and verification freshness. Show provenance and disagreement.

## Identity merge safety

- Explicit user confirmation outranks automated confidence; explicit user rejection blocks a pair.
- Matching external IDs are strong evidence only when the identifier namespace is authoritative and the value is well-formed.
- Same title with different creators, original languages, formats or adaptation clues may be different works.
- Translation, remake, spin-off, alternate cut, colored edition, and official/unofficial release can share a work relationship without sharing the same edition/chapter sequence.
- Merge operations must be reversible and auditable: retain source keys, former group IDs, reason, confidence, timestamp, and user action. Do not rewrite or delete user progress during a regrouping.
- If identity evidence changes, rebuild derived groups from immutable source listings rather than repeatedly merging already-merged records.

## Scale and resource limits

- The browser should not download hundreds of thousands of full listings at startup. Use paged repository indexes, incremental provider search, bounded metadata cache, and lazy details/chapters.
- Search result streaming should be cancellable. Stale query responses must not overwrite newer queries.
- Cap concurrent requests globally and per provider; respect rate limits and backoff; cache metadata separately from chapter image cache.
- Use IndexedDB indexes/compound keys for persisted catalog metadata and migrations for schema changes. Keep image/page caches evictable and user-owned library/progress non-evictable.
- Run large matching/index rebuilds in bounded batches; move CPU-heavy work to a worker when integrated. Yield between batches and surface progress/cancellation.
- Measure memory and request volume. Avoid keeping every chapter page URL or full image in memory at once.

## Current implementation status

The domain model already distinguishes Work, Edition, ProviderListing, Chapter, and ChapterListing. The current repository manager reads repository index metadata, but that alone is not an extension runtime or source catalogue. MangaDex is one provider implementation. The existing `universalCatalog.ts` and `universalSearch.ts` provide an initial pure domain/search foundation, including bounded concurrency and partial-source outcomes. They are not yet wired to a persisted global catalog index, extension runtime, merge review UI, or durable user-confirmed merge history.

## Acceptance gates before calling the ecosystem universal

- [ ] Repository index schema and trust/compatibility display
- [ ] Native extension contract + version compatibility checks
- [ ] Sandboxed execution or explicit supported adapter strategy
- [ ] Provider registry and enable/disable/update lifecycle
- [ ] Multi-provider search coordinator with cancellation, timeouts, partial outcomes, backoff
- [ ] IndexedDB catalog/listing indexes and safe migrations
- [ ] Search normalization and alias index
- [ ] Conservative work identity grouping, review/confirm/reject flow
- [ ] Edition/language/adaptation-aware chapter aggregation
- [ ] Latest-chapter comparison with source and translation provenance
- [ ] Reversible merge history and stable user-library/progress links
- [ ] Load tests with synthetic 100k+ listings, adversarial common titles and duplicate source IDs
- [ ] Build, typecheck, unit tests, APK workflow, and manual Android testing
