# KuroToon Architecture Proposal

This is a proposal, not a claim that the architecture is implemented. The final stack is intentionally left open until the first build and Android feasibility spikes provide evidence.

## Platform strategy

Target a shared product experience across web/PWA and Android, but do not assume every capability can be shared. Keep platform-specific features behind explicit interfaces.

The decision between a web-first PWA, a shared web UI packaged with Capacitor, and a more native Android implementation must account for:
- extension compatibility and host APIs,
- image-heavy reader performance,
- audio focus/background behaviour,
- file/storage permissions and offline downloads,
- accessibility and mobile lifecycle handling,
- developer effort and long-term maintenance.

A browser cannot directly execute Android APK extensions. Any Android compatibility path must be proven in a disposable spike before it becomes a production dependency.

## Logical layers

- **Screens and interactions:** Home, Browser, Reader, Library, Shop, Me.
- **Application services:** Search, Catalog, Progress, Collections, Recommendations, Reader timeline, Audio orchestration, Repository manager.
- **Domain model and policies:** Work, Edition, Listing, Chapter, Creator, Progress, Identity matching, Source provenance, Storage policy.
- **Capability interfaces:** Comic providers, Metadata providers, Speech providers, Cache/storage, Notifications, Platform lifecycle.
- **Platform adapters:** Web/PWA adapter, Android/native adapter, and test adapters.

UI code should not know the implementation details of a specific source or speech provider. Domain rules should be testable without a browser, network, or device.

## Provider contract

A provider adapter should expose capabilities such as:
- search(query, filters, cancellation)
- getWorkDetails(providerListingId)
- listChapters(providerListingId)
- getChapterPages(chapterListingId)
- health/status and capability metadata

Exact types will be defined in code. Every request should support cancellation and timeouts. Provider failures should be structured (blocked, unavailable, timeout, malformed response, unsupported operation) rather than collapsed into an empty result.

Concurrency and rate limits must be bounded per provider. Do not retry indefinitely or generate traffic that risks source bans. Respect applicable terms, access rules, and provider-specific constraints.

## Catalog identity

Do not use a URL as the sole identity of a series or chapter. URLs can change; different editions can share similar titles.

Recommended conceptual entities:
- **Work** — logical underlying story.
- **Edition** — language, adaptation, release, or other meaningful variant.
- **ProviderListing** — source-specific representation of a work/edition.
- **Chapter** — logical chapter when identity can be established.
- **ChapterListing** — provider-specific chapter record and page retrieval information.
- **Creator** — author/artist identity with source-specific evidence.
- **ReadingProgress** — durable progress associated with the logical reading target and, where needed, the edition.

Identity matching should combine evidence such as normalized titles, aliases, creators, language, chapter numbering, cover similarity where feasible, and cross-source links. Store confidence and provenance. Low-confidence matches remain separate until confirmed. User corrections override automated suggestions and should be reversible.

## Reading progress and persistence

Separate durable user data from disposable caches:
- Durable: library membership, statuses, categories, sort preferences, progress, history settings, identity corrections.
- Disposable: downloaded page responses, thumbnails, temporary search results, generated audio, temporary OCR output.

A cache purge must never delete durable library state. Source URL changes should not reset progress if a safe mapping exists. If the mapping is uncertain, ask or preserve both rather than silently moving progress.

## Reader timeline and audio

A single timeline should coordinate chapter position, optional panel/bubble sequence, audio cues, narration/dialogue playback, and auto-scroll. These systems must be optional and independently degradable.

Speech generation and OCR are provider capabilities, not hardwired UI functions. Model inferred speaker, text, order, emotion, and timing with confidence and user corrections. Persist only the minimum data needed and make external processing clear to the user.

Audio requirements:
- no unexpected loud autoplay,
- independent volume controls,
- global pause/mute,
- cancellation on chapter change and navigation,
- bounded prefetch and cache,
- platform audio-focus/lifecycle integration,
- graceful operation when audio or OCR is unavailable.

## Extension trust model

Treat third-party extensions as untrusted inputs. At minimum:
- record repository URL, extension identity/version, provenance, and update timestamp;
- validate repository and package metadata;
- define explicit capabilities and permissions;
- apply timeouts, cancellation, request budgets, and isolated error handling;
- never expose app secrets or unrestricted storage to a source;
- show unsupported/incompatible versions clearly;
- provide disable/remove and diagnostics controls.

Do not claim a JavaScript sandbox or APK isolation model is secure until it is implemented and reviewed. Native extension execution may carry broad privileges and must be evaluated separately.

## Search and result states

Search should distinguish:
- results found,
- no results after successful provider responses,
- partial results because some providers failed,
- still loading,
- offline/local-only results.

Use bounded parallelism and cancellation when the query changes. A timed-out source must not be represented as a confirmed empty result.

## Testing strategy

- Domain unit tests for identity, edition separation, chapter ordering, and progress mapping.
- Provider contract tests with deterministic fixtures.
- UI tests for navigation, loading/error/empty states, reader controls, and persistence.
- Integration tests for a complete search-to-page flow.
- Android/PWA smoke tests for lifecycle and capability differences.
- Performance checks for memory, image decoding, cache bounds, and source concurrency.

## Observability and privacy

Diagnostics should explain source failures without logging sensitive tokens, credentials, full personal reading history, or unnecessary content. External AI/TTS processing must be disclosed and opt-in where appropriate. Analytics should not be required for core reading.