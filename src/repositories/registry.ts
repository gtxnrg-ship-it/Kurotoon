export interface IndexedExtension {
  name: string;
  packageName?: string;
  version?: string;
  language?: string;
  contentWarning: boolean;
  sources: string[];
}

export interface ParsedRepositoryIndex {
  format: 'mihon-json-index';
  extensions: IndexedExtension[];
}

type JsonRecord = Record<string, unknown>;

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function optionalText(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  const trimmed = value.trim();
  return trimmed ? trimmed : undefined;
}

function safeSourceLabels(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    if (!isRecord(item)) return [];
    const name = optionalText(item.name);
    const baseUrl = optionalText(item.baseUrl);
    const label = name && baseUrl ? name + ' · ' + baseUrl : name || baseUrl;
    return label ? [label] : [];
  }).slice(0, 100);
}

/**
 * Accepts a direct HTTPS JSON index URL or a Mihon/Tachiyomi add-repository
 * deep link. Binary protobuf indexes cannot be read by this browser adapter.
 */
export function normalizeRepositoryUrl(input: string): string {
  const trimmed = input.trim();
  if (!trimmed) throw new Error('Enter a repository index URL.');

  let candidate = trimmed;
  if (/^(mihon|tachiyomi):\/\//i.test(candidate)) {
    let deepLink: URL;
    try {
      deepLink = new URL(candidate);
    } catch {
      throw new Error('That repository link is not valid.');
    }
    const embedded = deepLink.searchParams.get('url');
    if (!embedded) throw new Error('This add-repository link does not contain a URL.');
    candidate = embedded.trim();
  }

  let parsed: URL;
  try {
    parsed = new URL(candidate);
  } catch {
    throw new Error('Enter a complete repository URL, including https://.');
  }

  if (parsed.protocol !== 'https:') {
    throw new Error('For safety, repository indexes must use HTTPS.');
  }
  if (!parsed.hostname || parsed.username || parsed.password) {
    throw new Error('The repository URL must have a hostname and no embedded credentials.');
  }
  if (parsed.pathname.toLowerCase().endsWith('.pb')) {
    throw new Error('This is a binary index.pb file. The web build currently reads JSON indexes such as index.min.json; binary index support is not available yet.');
  }
  if (!parsed.pathname.toLowerCase().endsWith('.json')) {
    throw new Error('Use the direct JSON index URL, usually ending in index.min.json.');
  }

  parsed.hash = '';
  return parsed.toString();
}

/**
 * Parse the public Mihon/Tachiyomi legacy JSON index as catalogue metadata only.
 * This does not download, install, or execute the APK files referenced by entries.
 */
export function parseRepositoryIndex(payload: unknown): ParsedRepositoryIndex {
  if (!Array.isArray(payload)) {
    throw new Error('The URL did not return the expected JSON extension list.');
  }
  if (payload.length > 10000) {
    throw new Error('This index contains too many entries to safely display in the browser.');
  }

  const extensions: IndexedExtension[] = [];
  for (const item of payload) {
    if (!isRecord(item)) continue;

    const name = optionalText(item.name);
    const packageName = optionalText(item.pkg);
    const version = optionalText(item.version);
    const language = optionalText(item.lang);
    if (!name || (!packageName && !Array.isArray(item.sources))) continue;

    extensions.push({
      name,
      ...(packageName ? { packageName } : {}),
      ...(version ? { version } : {}),
      ...(language ? { language } : {}),
      contentWarning: item.nsfw === 1 || item.nsfw === true || item.nsfw === '1',
      sources: safeSourceLabels(item.sources),
    });
  }

  if (payload.length > 0 && extensions.length === 0) {
    throw new Error('The JSON file is not a recognised extension index.');
  }

  return { format: 'mihon-json-index', extensions };
}
