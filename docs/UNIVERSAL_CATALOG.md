# Universal catalog and identity architecture

Kurotoon is a source-agnostic reader and discovery client. It does not host comic chapters, and no catalog entry should imply that Kurotoon owns or republishes the underlying content. Every chapter must remain attributable to the provider from which it can actually be read.

## One story, many source records

The catalog treats these concepts separately:

- **Work:** the logical story/series. This is the stable, universal search result.
- **Edition:** a meaningful release or version, often language or adaptation-specific. Editions are not flattened simply because they share a Work.
- **Provider listing:** one source's record, title, URL, language, status, and identifiers. Always retained as provenance.
- **Chapter observation:** a source-specific report of a chapter and its publication/verification times. Chapter number by itself is not proof that one translation is newer.
- **Universal result:** a presentation aggregate built from one Work and its source listings, not a replacement for the source records.

A universal result can show one canonical title and alternative titles while still offering the user the exact source, edition, language, and chapter feed they choose. The canonical title is a display convention, not a claim that alternate titles or editions are invalid.

## Identity and duplicate policy

The current matching primitive combines normalized titles, aliases, globally comparable creator identity keys, and external identifiers. The batch catalog engine then uses bounded blocking indexes rather than comparing every record against every other record.

Automatic grouping is intentionally conservative:

1. A matching ID in a globally comparable external namespace is strong evidence, unless both records contradict one another in another shared namespace.
2. An exact normalized primary title plus an explicitly global creator identity is sufficient for the current auto-merge policy.
3. Provider-local creator IDs are never treated as globally comparable by default.
4. Title-only and alias-only matches can create a **review suggestion**, never an automatic merge.
5. A cluster is only combined when every pair of members supports the match. An ambiguous bridge record cannot silently combine conflicting clusters.

The universal-catalog grouping function is deterministic for a fixed set of inputs, retains every distinct provider listing, and labels the evidence behind the selected latest chapter. Its output identity key is an index key for the current input set; the persistence layer must retain a separately assigned stable Work ID and must never regenerate user-owned library keys from a display title.

## Canonical titles and alternate titles

A curated user title should eventually override all automated decisions. Until that persisted override exists, the batch engine chooses a display title deterministically: preferred language first (English by default), then source-title frequency and stable lexical tie-breakers. Other listing titles and source-supplied aliases remain discoverable. A title change must not change the saved Work ID, library membership, reading history, or progress.

## Latest chapter and translations

Publication timestamps are the highest-quality freshness evidence when providers supply valid timestamps. If none are available, the engine falls back to comparable numeric chapter labels, then provider verification time. Each chosen chapter retains its provider ID, URL, language, chapter label, and date evidence so the UI can explain where the update came from.

This is a ranking fallback, not proof that different numbered chapters across sources are the same logical chapter. Before cross-source chapter feeds are collapsed, the next phase must add explicit edition mapping, chapter-kind handling (regular / mini / special / extra / season break), and progress remapping. Mini-chapters must remain distinguishable from full chapters.

## Universal search pipeline

Expected flow:

1. The user submits one query and filters.
2. Enabled providers are queried concurrently under a bounded global concurrency limit and per-provider request budgets.
3. Each response is normalized to ProviderListing records with provider attribution intact.
4. The catalog groups high-confidence duplicates and emits capped review suggestions for ambiguous matches.
5. The result list displays one Work-level row when the identity evidence is sufficient; source and edition choices remain available under that row.
6. Results indicate partial failures instead of treating one broken provider as an empty catalog.
7. A background refresh updates chapter observations and provider health without blocking reading.

Search must support cancellation, timeout, source include/exclude filters, languages, formats, statuses, and pagination where a provider offers it. Provider errors must remain distinguishable from a genuine zero-result response.

## Scale and storage boundaries

The first grouping implementation uses title+global-creator and external-ID indexes to avoid an all-pairs scan. Potential-duplicate discovery uses capped title buckets and a hard suggestion limit so a generic title cannot generate an unbounded review queue. A real six-figure catalog still requires measured IndexedDB query plans, incremental ingestion, pagination, and memory-budget tests; do not claim six-figure production readiness merely because the algorithm has indexes.

Keep user-owned records (library, progress, manual identity corrections, preferences) separate from disposable provider listings, search responses, thumbnails, and page caches. Cache cleanup must never delete the user's library or progress. No remote account service or upload of reading history is implied.

## Extension ecosystem gate

Repository metadata and extension indexes are not themselves executable extensions. Mihon/Tachiyomi Android packages cannot be assumed to run inside browser JavaScript. The extension runtime must have a documented package format, API version, capability permissions, update/signature policy, network boundary, timeout budget, and failure isolation before extensions are advertised as installable. A compatibility claim requires a working proof of concept on the exact target (PWA and/or native Android).

Do not execute arbitrary extension strings with unrestricted eval or main-thread privileges. The initial target should be a documented Kurotoon provider API and explicit compatibility adapters where feasible, while repository discovery and extension installation remain honest about what is supported.
