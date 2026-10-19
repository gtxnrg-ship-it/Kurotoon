import type { ProviderListing } from '../domain/models';
import { assessWorkMatch, normalizeTitle, type WorkIdentityCandidate } from '../domain/identity';

export interface LatestChapterObservation {
  providerId: string;
  providerWorkId: string;
  providerChapterId: string;
  chapterLabel: string;
  title?: string;
  url: string;
  languageCode?: string;
  publishedAt?: string;
  lastVerifiedAt?: string;
  kind?: string;
}

export interface CatalogListingInput {
  listing: ProviderListing;
  /** IDs in globally comparable namespaces (for example MAL or AniList). */
  externalIds?: Record<string, string>;
  /**
   * Explicit, globally comparable creator identities only. Do not pass a
   * provider-local creator ID here unless it has been mapped to a global ID.
   */
  creatorIdentityKeys?: string[];
  latestChapter?: LatestChapterObservation;
}

export type FreshnessBasis = 'published-at' | 'chapter-number' | 'last-verified';

export interface UniversalWorkResult {
  /** Deterministic for a fixed input set; persistence should retain its own ID. */
  identityKey: string;
  canonicalTitle: string;
  aliases: string[];
  /** Every source listing remains available; merging never discards provenance. */
  listings: ProviderListing[];
  sourceIds: string[];
  languageCodes: string[];
  latestChapter?: LatestChapterObservation;
  latestChapterBasis?: FreshnessBasis;
  matchConfidence: number;
}

export interface DuplicateSuggestion {
  leftListingKey: string;
  rightListingKey: string;
  leftTitle: string;
  rightTitle: string;
  confidence: number;
  reasons: string[];
}

export interface UniversalCatalogOptions {
  /** Defaults to English when selecting a display title. */
  preferredLanguageCode?: string;
  /** Maximum review suggestions emitted by the bounded duplicate scan. */
  maxDuplicateSuggestions?: number;
}

interface NormalizedInput {
  listing: ProviderListing;
  externalIds: Record<string, string>;
  creatorIdentityKeys: string[];
  latestChapters: LatestChapterObservation[];
}

interface WorkCluster {
  id: string;
  members: NormalizedInput[];
  seedKey: string;
}

function normalizedId(value: string): string {
  return value.normalize('NFKC').trim().toLocaleLowerCase();
}

function validTimestamp(value?: string): number | undefined {
  if (!value) return undefined;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function listingKey(listing: Pick<ProviderListing, 'providerId' | 'providerWorkId'>): string {
  return listing.providerId + ':' + listing.providerWorkId;
}

function compareText(left: string, right: string): number {
  return left.localeCompare(right, 'en', { sensitivity: 'base' }) || left.localeCompare(right);
}

function normalizeInput(input: CatalogListingInput): NormalizedInput {
  const externalIds: Record<string, string> = {};
  for (const [namespace, rawId] of Object.entries(input.externalIds ?? {})) {
    const cleanNamespace = normalizedId(namespace);
    const cleanId = normalizedId(rawId);
    if (cleanNamespace && cleanId) externalIds[cleanNamespace] = cleanId;
  }
  return {
    listing: input.listing,
    externalIds,
    creatorIdentityKeys: [...new Set((input.creatorIdentityKeys ?? [])
      .map(normalizedId).filter(Boolean))].sort(),
    latestChapters: input.latestChapter ? [input.latestChapter] : [],
  };
}

function mergeDuplicateInput(existing: NormalizedInput, incoming: NormalizedInput): NormalizedInput {
  const existingVerified = validTimestamp(existing.listing.lastVerifiedAt) ?? -Infinity;
  const incomingVerified = validTimestamp(incoming.listing.lastVerifiedAt) ?? -Infinity;
  const preferred = incomingVerified > existingVerified ? incoming : existing;
  const other = preferred === incoming ? existing : incoming;
  const externalIds = { ...existing.externalIds };
  for (const [namespace, id] of Object.entries(incoming.externalIds)) {
    if (!externalIds[namespace]) externalIds[namespace] = id;
  }
  const aliases = uniqueDisplayValues([
    ...preferred.listing.aliases,
    ...other.listing.aliases,
    other.listing.title,
  ]).filter(value => normalizeTitle(value) !== normalizeTitle(preferred.listing.title));
  const creatorKeys = new Set<string>();
  const creators = [...preferred.listing.creators, ...other.listing.creators].filter(creator => {
    const key = [creator.providerId ?? '', creator.id ?? '', creator.role ?? '', normalizedId(creator.name)].join(':');
    if (creatorKeys.has(key)) return false;
    creatorKeys.add(key);
    return true;
  });
  return {
    listing: { ...preferred.listing, aliases, creators },
    externalIds,
    creatorIdentityKeys: [...new Set([...existing.creatorIdentityKeys, ...incoming.creatorIdentityKeys])].sort(),
    latestChapters: [...existing.latestChapters, ...incoming.latestChapters],
  };
}

function identityCandidate(input: NormalizedInput): WorkIdentityCandidate {
  return {
    title: input.listing.title,
    aliases: input.listing.aliases,
    creatorIds: input.creatorIdentityKeys,
    externalIds: input.externalIds,
  };
}

function safeAutoMatch(left: NormalizedInput, right: NormalizedInput): boolean {
  // Conflicting values in the same authoritative identifier namespace are a
  // hard stop even when a title happens to match.
  for (const [namespace, leftId] of Object.entries(left.externalIds)) {
    const rightId = right.externalIds[namespace];
    if (rightId && rightId !== leftId) return false;
  }
  return assessWorkMatch(identityCandidate(left), identityCandidate(right)).autoMerge;
}

function externalIndexKeys(input: NormalizedInput): string[] {
  return Object.entries(input.externalIds)
    .map(([namespace, id]) => 'external:' + namespace + ':' + id)
    .sort();
}

function identityIndexKeys(input: NormalizedInput): string[] {
  const title = normalizeTitle(input.listing.title).replace(/^(?:the|a|an)\s+/u, '');
  if (!title || input.creatorIdentityKeys.length === 0) return externalIndexKeys(input);
  return [...externalIndexKeys(input), ...input.creatorIdentityKeys.map(key => 'title-creator:' + title + ':' + key)];
}

function clusterIdentityKey(members: NormalizedInput[]): string {
  const keySets = members.map(member => new Set(identityIndexKeys(member)));
  const common = [...(keySets[0] ?? [])].filter(key => keySets.every(keys => keys.has(key))).sort();
  const preferred = common.find(key => key.startsWith('external:')) ?? common[0];
  if (preferred) return preferred;
  return 'listing:' + members.map(member => listingKey(member.listing)).sort()[0];
}

function pickCanonicalTitle(members: NormalizedInput[], preferredLanguageCode: string): string {
  const counts = new Map<string, { title: string; count: number; languageRank: number }>();
  const preferred = normalizedId(preferredLanguageCode);
  for (const member of members) {
    const title = member.listing.title.trim();
    const normalized = normalizeTitle(title);
    if (!normalized) continue;
    const language = normalizedId(member.listing.languageCode ?? '');
    const languageRank = preferred && (language === preferred || language.startsWith(preferred + '-')) ? 0 : 1;
    const existing = counts.get(normalized);
    if (!existing) counts.set(normalized, { title, count: 1, languageRank });
    else {
      existing.count += 1;
      existing.languageRank = Math.min(existing.languageRank, languageRank);
      if (title.length < existing.title.length) existing.title = title;
    }
  }
  return [...counts.values()].sort((a, b) =>
    a.languageRank - b.languageRank ||
    b.count - a.count ||
    compareText(normalizeTitle(a.title), normalizeTitle(b.title)) ||
    compareText(a.title, b.title),
  )[0]?.title ?? 'Untitled series';
}

function uniqueDisplayValues(values: string[]): string[] {
  const byNormalized = new Map<string, string>();
  for (const raw of values) {
    const value = raw.trim();
    const key = normalizeTitle(value);
    if (key && !byNormalized.has(key)) byNormalized.set(key, value);
  }
  return [...byNormalized.entries()].sort(([a], [b]) => compareText(a, b)).map(([, value]) => value);
}

function chapterNumber(value: string): number | undefined {
  const match = value.trim().match(/^(?:chapter\s*)?(\d+(?:\.\d+)?)(?:\b|$)/i);
  if (!match) return undefined;
  const parsed = Number(match[1]);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function chooseLatestChapter(
  chapters: LatestChapterObservation[],
): { chapter?: LatestChapterObservation; basis?: FreshnessBasis } {
  if (chapters.length === 0) return {};
  const dated = chapters
    .map(chapter => ({ chapter, timestamp: validTimestamp(chapter.publishedAt) }))
    .filter((item): item is { chapter: LatestChapterObservation; timestamp: number } => item.timestamp !== undefined);
  if (dated.length > 0) {
    dated.sort((a, b) =>
      b.timestamp - a.timestamp ||
      (validTimestamp(b.chapter.lastVerifiedAt) ?? -Infinity) - (validTimestamp(a.chapter.lastVerifiedAt) ?? -Infinity) ||
      compareText(a.chapter.providerId, b.chapter.providerId),
    );
    return { chapter: dated[0].chapter, basis: 'published-at' };
  }

  const numbered = chapters
    .map(chapter => ({ chapter, number: chapterNumber(chapter.chapterLabel) }))
    .filter((item): item is { chapter: LatestChapterObservation; number: number } => item.number !== undefined);
  if (numbered.length > 0) {
    numbered.sort((a, b) =>
      b.number - a.number ||
      (validTimestamp(b.chapter.lastVerifiedAt) ?? -Infinity) - (validTimestamp(a.chapter.lastVerifiedAt) ?? -Infinity),
    );
    return { chapter: numbered[0].chapter, basis: 'chapter-number' };
  }

  return {
    chapter: [...chapters].sort((a, b) =>
      (validTimestamp(b.lastVerifiedAt) ?? -Infinity) - (validTimestamp(a.lastVerifiedAt) ?? -Infinity),
    )[0],
    basis: 'last-verified',
  };
}

function dedupeSourceListings(inputs: NormalizedInput[]): NormalizedInput[] {
  const byKey = new Map<string, NormalizedInput>();
  for (const input of inputs) {
    const key = listingKey(input.listing);
    const existing = byKey.get(key);
    byKey.set(key, existing ? mergeDuplicateInput(existing, input) : input);
  }
  return [...byKey.values()].sort((a, b) => compareText(listingKey(a.listing), listingKey(b.listing)));
}

/**
 * Groups source listings into source-independent story results.
 *
 * Uses blocking indexes (external identifier and exact normalized title +
 * globally comparable creator ID), not an all-pairs scan. Title alone and
 * provider-local creator IDs are never enough to auto-merge. Source listings,
 * URLs, languages, and latest chapter observations are retained.
 */
export function buildUniversalCatalog(
  rawInputs: CatalogListingInput[],
  options: UniversalCatalogOptions = {},
): UniversalWorkResult[] {
  const inputs = dedupeSourceListings(rawInputs.map(normalizeInput));
  const preferredLanguageCode = options.preferredLanguageCode ?? 'en';
  const clusters = new Map<string, WorkCluster>();
  const clusterIdsByIndexKey = new Map<string, Set<string>>();
  let nextClusterNumber = 0;

  const indexCluster = (cluster: WorkCluster, input: NormalizedInput) => {
    for (const key of identityIndexKeys(input)) {
      let ids = clusterIdsByIndexKey.get(key);
      if (!ids) {
        ids = new Set<string>();
        clusterIdsByIndexKey.set(key, ids);
      }
      ids.add(cluster.id);
    }
  };

  const everyPairMatches = (members: NormalizedInput[]): boolean => {
    for (let i = 0; i < members.length; i += 1) {
      for (let j = i + 1; j < members.length; j += 1) {
        if (!safeAutoMatch(members[i], members[j])) return false;
      }
    }
    return true;
  };

  for (const input of inputs) {
    const matchingClusterIds = new Set<string>();
    for (const key of identityIndexKeys(input)) {
      for (const id of clusterIdsByIndexKey.get(key) ?? []) {
        if (clusters.has(id)) matchingClusterIds.add(id);
      }
    }
    const matchingClusters = [...matchingClusterIds]
      .map(id => clusters.get(id)!)
      .filter(cluster => cluster.members.every(member => safeAutoMatch(member, input)))
      .sort((a, b) => compareText(a.seedKey, b.seedKey));

    if (matchingClusters.length === 0) {
      const cluster: WorkCluster = {
        id: 'cluster-' + (++nextClusterNumber),
        members: [input],
        seedKey: listingKey(input.listing),
      };
      clusters.set(cluster.id, cluster);
      indexCluster(cluster, input);
      continue;
    }

    const target = matchingClusters[0];
    const proposedMembers = [...target.members, input];
    const mergeableClusters = matchingClusters.slice(1).filter(other =>
      everyPairMatches([...proposedMembers, ...other.members]),
    );
    target.members.push(input);
    indexCluster(target, input);
    for (const other of mergeableClusters) {
      target.members.push(...other.members);
      clusters.delete(other.id);
      for (const member of other.members) indexCluster(target, member);
    }
  }

  const results: UniversalWorkResult[] = [];
  for (const cluster of clusters.values()) {
    const members = cluster.members;
    const canonicalTitle = pickCanonicalTitle(members, preferredLanguageCode);
    const canonicalNormalized = normalizeTitle(canonicalTitle);
    const aliases = uniqueDisplayValues(members.flatMap(member => [
      member.listing.title,
      ...member.listing.aliases,
    ])).filter(value => normalizeTitle(value) !== canonicalNormalized);
    const latest = chooseLatestChapter(members.flatMap(member => member.latestChapters));
    const pairScores: number[] = [];
    for (let i = 0; i < members.length; i += 1) {
      for (let j = i + 1; j < members.length; j += 1) {
        pairScores.push(assessWorkMatch(identityCandidate(members[i]), identityCandidate(members[j])).confidence);
      }
    }
    const identityKey = clusterIdentityKey(members);
    results.push({
      identityKey,
      canonicalTitle,
      aliases,
      listings: members.map(member => member.listing).sort((a, b) =>
        (validTimestamp(b.lastVerifiedAt) ?? -Infinity) - (validTimestamp(a.lastVerifiedAt) ?? -Infinity) ||
        compareText(listingKey(a), listingKey(b)),
      ),
      sourceIds: [...new Set(members.map(member => member.listing.providerId))].sort(),
      languageCodes: [...new Set(members.map(member => member.listing.languageCode).filter((value): value is string => Boolean(value)))].sort(),
      ...(latest.chapter ? { latestChapter: latest.chapter } : {}),
      ...(latest.basis ? { latestChapterBasis: latest.basis } : {}),
      matchConfidence: pairScores.length > 0 ? Math.min(...pairScores) : 1,
    });
  }

  return results.sort((a, b) =>
    (validTimestamp(b.latestChapter?.publishedAt) ?? -Infinity) - (validTimestamp(a.latestChapter?.publishedAt) ?? -Infinity) ||
    b.sourceIds.length - a.sourceIds.length ||
    compareText(a.canonicalTitle, b.canonicalTitle),
  );
}

/**
 * Emits bounded, human-reviewable duplicate suggestions. These are not merged.
 * A title bucket is capped to avoid quadratic behaviour for common titles.
 */
export function suggestPotentialDuplicates(
  rawInputs: CatalogListingInput[],
  options: { maxSuggestions?: number; maxPerTitleBucket?: number } = {},
): DuplicateSuggestion[] {
  const maxSuggestions = Math.max(0, Math.floor(options.maxSuggestions ?? 250));
  const maxPerTitleBucket = Math.max(2, Math.floor(options.maxPerTitleBucket ?? 48));
  if (maxSuggestions === 0) return [];
  const inputs = dedupeSourceListings(rawInputs.map(normalizeInput));
  const buckets = new Map<string, NormalizedInput[]>();
  for (const input of inputs) {
    const titles = uniqueDisplayValues([input.listing.title, ...input.listing.aliases])
      .map(normalizeTitle).filter(Boolean);
    for (const title of titles) {
      let bucket = buckets.get(title);
      if (!bucket) {
        bucket = [];
        buckets.set(title, bucket);
      }
      if (bucket.length < maxPerTitleBucket) bucket.push(input);
    }
  }

  const suggestions: DuplicateSuggestion[] = [];
  const seenPairs = new Set<string>();
  const orderedBuckets = [...buckets.entries()].sort(([a], [b]) => compareText(a, b));
  for (const [, bucket] of orderedBuckets) {
    for (let i = 0; i < bucket.length && suggestions.length < maxSuggestions; i += 1) {
      for (let j = i + 1; j < bucket.length && suggestions.length < maxSuggestions; j += 1) {
        const left = bucket[i];
        const right = bucket[j];
        const leftKey = listingKey(left.listing);
        const rightKey = listingKey(right.listing);
        if (leftKey === rightKey) continue;
        const orderedKeys = [leftKey, rightKey].sort();
        const pairKey = orderedKeys.join('\u001f');
        if (seenPairs.has(pairKey)) continue;
        seenPairs.add(pairKey);
        const assessment = assessWorkMatch(identityCandidate(left), identityCandidate(right));
        if (assessment.autoMerge || assessment.confidence < 0.5) continue;
        suggestions.push({
          leftListingKey: orderedKeys[0],
          rightListingKey: orderedKeys[1],
          leftTitle: left.listing.title,
          rightTitle: right.listing.title,
          confidence: assessment.confidence,
          reasons: assessment.reasons,
        });
      }
    }
    if (suggestions.length >= maxSuggestions) break;
  }
  return suggestions.sort((a, b) =>
    b.confidence - a.confidence ||
    compareText(a.leftListingKey, b.leftListingKey) ||
    compareText(a.rightListingKey, b.rightListingKey),
  );
}
