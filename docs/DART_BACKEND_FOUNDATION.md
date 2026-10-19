# Kurotoon Dart backend foundation

## Direction

The long-term app UI target is Flutter/Dart. The old React/TypeScript/Vite + Capacitor application remains the current main-branch prototype until a tested Flutter replacement exists; it must not be described as already migrated or native. Domain behavior is being moved into a platform-independent Dart package first, so Flutter does not become a thin shell over a web application.

## Workspace

- `packages/kurotoon_core`: pure Dart catalog/domain rules, source coordination, progress reconciliation, safety policy, bounded cache planning, and reader event filtering.
- `apps/kurotoon_flutter`: Flutter workspace consuming the core. No polished screen tree belongs in the backend phase.
- `.github/workflows/dart-core.yml`: analyzes and tests the domain package on relevant changes.

## Backend invariants

- Cross-source matching preserves provenance and never auto-merges on title alone. Conflicting publication years or formats veto an automatic match; uncertain candidates remain reviewable.
- Provider search has a concurrency limit, a request deadline, cooperative cancellation, safe error messages, and explicit partial/blocked/timeout statuses. Network adapters must connect the token to the underlying client's actual cancellation/abort support.
- MangaDex remains an ordinary built-in provider that can be disabled by the user; built-in source IDs cannot be accidentally removed as if they were community installs.
- Repository URLs require HTTPS and reject common local/private hosts. This is an initial validation gate, not a complete SSRF defense: adapters must re-check resolved IPs and redirect targets and must not execute untrusted provider code in the app's main isolate.
- Reading progress uses deterministic timestamp/revision reconciliation and allows a newer intentional rewind.
- Cache planning defaults to 1.5 GiB and evicts only unpinned cache entries; it does not manage user library, preferences, or progress. User-owned offline data must be represented explicitly and must never be silently deleted.
- Reader audio/voice/haptic cues share one chapter-relative timeline. All channels are opt-in, inferred dialogue is separately gated, and low-confidence/foreign-chapter cues are ignored.
- Platform adapters will supply actual network, database, secure-storage, audio, voice, haptic, and lifecycle integrations; the core package contains deterministic policy and domain logic, not pretend device implementations.

## Verification

The Dart CI workflow runs formatting checks, static analysis, and unit tests for the core. Real device performance, real HTTP cancellation, provider compatibility, disk eviction execution, and platform media/haptics remain integration-test gates rather than claimed completed features.
