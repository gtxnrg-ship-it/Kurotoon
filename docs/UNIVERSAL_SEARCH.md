# Universal search orchestration

```text
query → enabled provider adapters → bounded worker pool → validated source listings + per-source outcomes
                                              ↓
                                  universal catalog grouping
                                              ↓
                  work-level result + aliases + source/edition choices
```

The Browser must call a shared search service, never a specific provider directly. The orchestration layer is responsible for cancellation, request budget, bounded concurrency, result validation, source attribution, deduplication within one provider, and partial failures. Each provider adapter remains responsible for its source protocol, pagination semantics, and source-specific rate limits.

## Search behavior

- Blank queries do no network work.
- Only providers in the enabled-source allowlist participate.
- A global bounded worker pool prevents one search from firing at hundreds of adapters simultaneously.
- Each source has a timeout and gets an AbortSignal. Cancellation is reported as cancellation, not “no results.”
- A response with malformed listings or mismatched provider IDs fails as invalid-response instead of leaking another source's attribution.
- Duplicate rows for the same provider/work are coalesced using the newest valid verification timestamp, without merging different providers.
- Outcomes are ordered by provider registry order, not network completion order.
- A provider that returned zero valid listings is “empty.” Errors preserve their failure code and retryability. A result with any source failure is marked partial.
- Catalog grouping happens after this layer; the universal catalog must keep source listings and alternates intact.

## What this does not do yet

The service is a reusable orchestration seam, not proof that hundreds of sources already exist. A provider must be registered and enabled before it can contribute results. Pagination and incremental local metadata indexing are later work. Provider implementations must honour cancellation where possible and must apply their own source-specific request policies. The app still needs Browser UI wiring to this service, followed by the universal catalog aggregate UI and real multi-provider acceptance tests.

Kurotoon remains a client: source listings and chapter page URLs keep their original source provenance. No chapter content is hosted by this service.
