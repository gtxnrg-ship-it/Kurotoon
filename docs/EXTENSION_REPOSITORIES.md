# KuroToon Extension Repositories

> **Runtime status:** the Flutter/Dart repository and declarative-manifest services are implemented as backend foundations; the complete native repository browser/install-management UI is not yet finished. Do not tell users that Mihon/Tachiyomi APK extensions are compatible. The supported initial format is declarative JSON handled by KuroToon's constrained endpoint adapter.

A repository is untrusted metadata. Adding a repository must preview its identity and require user confirmation. Installing one extension must be a separate explicit action. Never execute arbitrary downloaded code or bulk-download all catalogue entries because a repository was added.


## User experience

A repository is a catalogue URL, not a bulk download. The user adds one HTTPS index URL; KuroToon fetches the small index, shows its extensions, and downloads an individual declarative manifest only after the user selects Install.

The app must never download or execute every entry merely because a repository was added.

## Add-repository links

The app link format is:

\`kurotoon://add-repo?url=<percent-encoded-HTTPS-index-URL>\`

The link only pre-fills a repository address. KuroToon must show the repository identity and trust warning and require user confirmation before adding it. The deep-link parser is not a substitute for validating the URL or fetching the index safely.

Manual entry, paste, QR scan, and share/open links should all call the same repository service.

## Index format, schema version 1

An index is JSON served over HTTPS. The canonical filename may be \`index.min.json\`; the filename itself is not trusted as proof of validity.

\`\`\`json
{
  "schemaVersion": 1,
  "id": "org.example.repository",
  "name": "Example Repository",
  "description": "Community-maintained declarative sources",
  "website": "https://example.org",
  "generatedAt": "2026-10-19T00:00:00Z",
  "extensions": [
    {
      "id": "org.example.source",
      "name": "Example Source",
      "version": "1.0.0",
      "manifestUrl": "manifests/example-source.json",
      "sha256": "REPLACE_WITH_64_HEX_SHA256_DIGEST",
      "sizeBytes": 1234,
      "minimumAppApi": 1,
      "capabilities": ["search"],
      "languageCodes": ["en"],
      "contentRating": "safe"
    }
  ]
}
\`\`\`

The sample digest is a placeholder and is deliberately not installable. Each entry's digest and exact byte count must be generated from the published manifest bytes.

## Declarative extension manifest

The first supported extension format is declarative JSON, not a downloaded Dart library or Android APK. A manifest declares a public HTTPS API base URL, exact allowed hostnames, a license, endpoint paths, query placeholders, JSON result paths, and field mappings. It cannot contain executable code.

\`\`\`json
{
  "id": "org.example.source",
  "name": "Example Source",
  "version": "1.0.0",
  "minimumAppApi": 1,
  "homepage": "https://source.example.org",
  "baseUrl": "https://api.source.example.org/v1",
  "license": "MIT",
  "developer": "Example Maintainers",
  "allowedHosts": [
    "api.source.example.org",
    "source.example.org"
  ],
  "enabledByDefault": false,
  "endpoints": [
    {
      "id": "search",
      "capability": "search",
      "path": "/search",
      "query": {
        "q": "{query}",
        "page": "{page}",
        "limit": "{limit}"
      },
      "resultPath": ["data", "items"],
      "fields": {
        "id": ["id"],
        "title": ["title"],
        "url": ["url"],
        "coverUrl": ["cover"],
        "creatorNames": ["authors"],
        "year": ["year"],
        "format": ["format"]
      },
      "maxResponseBytes": 1048576
    }
  ]
}
\`\`\`

Every endpoint is validated before use. Only declared capabilities and supported placeholders are accepted. URL paths cannot use authority syntax or traversal segments. Hostnames are exact rather than wildcard patterns. Redirects are rejected by the initial HTTP client; repository authors should publish stable direct HTTPS URLs.

## Install lifecycle

1. Validate the entered index URL as HTTPS, without credentials, local/private hosts, custom ports, or fragments.
2. Fetch the index with connection/read timeouts and a strict response-byte cap.
3. Parse the supported schema and reject duplicate extension IDs, unsupported API versions, malformed hashes, excessive package sizes, and package URLs on a different origin.
4. Show repository identity, extension details, source website, license, language, content rating, and a third-party trust warning.
5. After explicit install confirmation, download only the selected manifest.
6. Verify exact byte count and SHA-256, parse the manifest, and require its ID/version/API/capabilities to match the index.
7. Store the manifest in app support storage and persist install provenance in SQLite. New installs remain disabled until the user enables them.
8. Register enabled manifests through the declarative provider adapter. Uninstall removes its stored manifest and provider registration without deleting the user's library or progress.
9. On refresh, preserve repository identity and show version/digest changes. Do not silently switch an installed extension to a different repository with the same ID.

## Trust and network boundaries

- Adding a repository is a user trust decision, not a guarantee that its contents are safe.
- SHA-256 detects byte mismatches relative to the index, but does not authenticate the publisher if an attacker can alter both the index and package. A future signed-index format should pin publisher public keys and verify signatures before installs.
- HTTPS syntax validation alone does not prevent DNS rebinding. Resolve and reject non-public IP ranges before requests; network transports must also revalidate every redirect target. Current transport refuses redirects rather than following them.
- Extension endpoints use bounded JSON GET requests only. Arbitrary JavaScript, Dart, native libraries, APKs, file-system access, and arbitrary outbound hosts are not accepted by the declarative runtime.
- iOS, Android, Windows, and Linux should use the same manifest and index format. A complex source requiring executable code needs a separately designed, permissioned sandbox; it must not silently fall back to unrestricted execution.
- The current HTTP transport's DNS pre-check is a defense-in-depth check, not a complete pinned-connection DNS-rebinding guarantee. Do not claim hostile-network isolation is complete until the transport pins validated addresses or uses a suitable platform networking layer.

## Storage and updates

Only repository metadata, installed manifests, and explicit user state are persisted. The catalogue is refreshed on demand; the app does not bulk-download all source packages. Package sizes and response sizes are bounded. Source uninstall must not remove the user's saved series, editions, reading progress, or creator records.
