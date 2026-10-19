# KuroToon Native Android Preview

This is the separate Kotlin + Jetpack Compose application track. It does **not** use React, Vite, Capacitor, or a WebView for the app UI. The existing TypeScript app is preserved as a reference and migration source while parity is built feature by feature.

## Try the preview APK

- [Open native Android workflow runs](https://github.com/gtxnrg-ship-it/Kurotoon/actions/workflows/native-android.yml)
- On a successful run, download the **Kurotoon-Native-Preview** artifact. Pull-request artifacts are retained for 14 days.
- After native changes are merged to `main`, successful workflow runs also publish a separate prerelease on [GitHub Releases](https://github.com/gtxnrg-ship-it/Kurotoon/releases).

This preview is for inspection, not a production-ready reader release. It uses a distinct Android application ID suffix so that it can be installed alongside an older prototype.

## What is currently implemented in this preview

- Native Compose home surface using the KuroToon Galaxy palette.
- Procedural, slowly drifting colour-shifting nebulae; twinkling stars; subtle filaments; a sparse shooting-star trail; and temporary touch ripples, all drawn on one canvas.
- System animation-scale respect plus a persisted Galaxy-motion preference.
- Live MangaDex trending metadata and cover-art thumbnails, with bounded response size and request timeouts. Cover assets are requested directly from MangaDex; KuroToon does not bundle or re-host comic artwork.
- A preview-only navigation contract: Home is open; Browser, categories/filters, Shop, Library, Me, and settings are visibly locked rather than pretending those sections are finished.
- Native provider registry and bounded-concurrency universal search seam with per-provider timeouts and partial-failure outcomes.
- Conservative Work identity scoring and a bounded candidate-pair catalog merger, with ambiguous overlaps sent to review suggestions.
- Room data entities for works, provider listings, library entries, reading progress, and provider configuration; DataStore preferences separate user choices from provider/cache data.
- Optional haptics, system TTS fallback, and explicit-start ambient audio controller. No sound starts automatically.

## Build from source

Requires JDK 17, Android SDK platform 36, and Gradle 8.13.

```bash
cd native-android
gradle testDebugUnitTest assembleDebug
```

The preview does not yet ship a bundled neural voice model, full provider extension runtime, production reader, or production library UI. Open-source on-device TTS is an explicit next integration gate: the engine and model need ABI, license, size, checksum, cancellation, device-memory, and playback tests before being advertised as ready. The reader and provider migration remain incremental work; this preview is intentionally honest about its scope.

## Experience and data rules

- Live-first operation; no forced account and no automatic upload of reading history.
- User-owned library/progress must remain separate from disposable provider observations and cover caches.
- Audio is opt-in and must support pause/stop and independent volume. Narration inference must not be presented as ground truth.
- Haptics and motion are optional; reduced-motion system settings are respected.
- Source metadata, listing URLs, and artwork remain attributable to the original provider.
