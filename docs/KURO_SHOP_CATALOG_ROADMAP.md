# Kuro Shop collectible roadmap

## Launch catalog: 60 entries

The launch catalog is intentionally split into five tiers:

| Tier | Count | Purpose |
|---|---:|---|
| Standard | 25 | Core Kuru expressions and everyday collectibles |
| Premium | 12 | Higher-value character and cosmetic collectibles, including Gojo and Akira entries |
| Top 10 | 10 | Showcase designs chosen for exceptional visual quality |
| Community rewards | 10 | Contribution, founding-user, participation, and milestone rewards |
| Legendary | 3 | Progenitor, Celestial, and Cute Kuro |
| **Total** | **60** | |

The three legendary entries and ten community rewards use achievement currency and are not purchasable with the local wallet. Their current unlock descriptions are product rules, not secure enforcement. Before public release, the backend must verify account identity, contribution status, milestones, and grants.

## Expansion target: 173

The long-term catalog target remains 173 collectibles. Keep the 60-item launch collection stable and add the remaining 113 through reviewed releases. New batches should prioritize:
1. Individual source-faithful crops from the original Kuru reference board.
2. Additional Kuru expressions, outfits, seasonal artwork, poses, and avatars.
3. Premium original characters and legally cleared fan/official character material.
4. Contributor/user recognition rewards that are earned fairly.
5. Additional cosmetics only when the artwork is distinct and quality-checked.

## Artwork quality gate

Do not mark an item as artwork-complete because it has an icon or placeholder. Each artwork-backed catalog entry should have an explicit asset path, a checked source region, an image-load test, and a visual review at the Shop card and detail-preview sizes. Upscaling may improve display sizing but cannot recover details absent from the flattened source board. Never use generative redraws as if they were the supplied original artwork.

## Current limitations

- The current catalog tier model and unlock descriptions are implemented in Flutter.
- Wallet and ownership still use local storage. They are not account-synced and can be modified on-device.
- Google sign-in, verified admin authorization, backend-owned wallets, and cross-device restoration are not implemented yet.
- The flattened source reference board still needs a complete item-by-item crop inventory and image QA pass.


## Deployment constraint: no mandatory paid services

The Shop must remain useful without a backend, a self-hosted server, a payment method, or a subscription. The current local wallet and ownership database are prototype/local-device state, not secure online entitlements. Keep catalog browsing and local collection features functional offline. Do not advertise cross-device sync, secure achievements, online purchase validation, or server-verified administrator grants until a trusted backend is deployed and tested.

A hosted free tier may be considered only after confirming that signup and continued use do not require billing activation or payment details, and documenting quotas, pause/expiry behavior, and failure handling. If no acceptable service meets those constraints, leave online-only features deferred instead of introducing a paid dependency or insecure client-side workaround.


## First local earning loop

The first offline reward loop is intentionally small and transparent:

- A reader may claim **20 silver once per work + edition + chapter** using the completion checkmark shown on the final page.
- The completion ledger and wallet update are written in one local database transaction, so repeated taps do not duplicate the reward.
- The Shop explicitly explains the local-only nature of the reward and offers refresh when returning from the reader.
- This is a convenience feature, not anti-cheat protection: local data can be modified by a device owner. Do not use it as proof for online achievements, contributor rewards, or administrator grants.
- The reward amount is a starter economy value and should be balanced with actual catalog prices and reading behavior before any production economy is announced.
