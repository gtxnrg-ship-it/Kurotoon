import type { ChapterListing, ProviderListing } from './models';
import { assessWorkMatch, normalizeTitle, type WorkIdentityCandidate } from './identity';

export interface CatalogListing extends ProviderListing {
  /** Stable source identity, never a universal series identity. */
  sourceKey: string;
  /** Normalized candidate identity used for blocking and indexing. */
  normalizedTitle: string;
}

export interface CatalogGroup {
  /** Deterministic ID derived from the strongest available identity evidence. */
  id: string;
  canonicalTitle: string;
  aliases: string[];
  listings: CatalogListing[];
  confidence: number;
  needsReview: boolean;
}

export interface CatalogMergeOptions {
  /** Explicitly confirmed equivalences. Each pair contains sourceKey values. */
  confirmedPairs?: Array<[string, string]>;
  /** Explicitly distinct pairs that must never be grouped together. */
  rejectedPairs?: Array<[string, string]>;
  /** Optional canonical title chosen by the user, keyed by stable group id. */
  canonicalTitles?: Record<string, string>;
}

function sourceKey(listing: ProviderListing): string {
  return listing.providerId + ':' + listing.providerWorkId;
}

function candidate(listing: ProviderListing): WorkIdentityCandidate {
  return {
    title: listing.title,
    aliases: listing.aliases,
    creatorIds: listing.creators.flatMap((creator) => creator.id ? [creator.providerId ? creator.providerId + ':' + creator.id : creator.id] : []),
    externalIds: listing.externalIds,
  };
}

function creatorNames(listing: ProviderListing): string[] {
  return listing.creators.map((creator) => normalizeTitle(creator.name)).filter(Boolean);
}

function pairKey(left: string, right: string): string {
  return left < right ? left + '\u0000' + right : right + '\u0000' + left;
}

function stableId(keys: string[]): string {
  // Stable, dependency-free FNV-1a hash; source keys are sorted before hashing.
  const value = [...keys].sort().join('|');
  let hash = 0x811c9dc5;
  for (let i = 0; i < value.length; i += 1) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return 'work-' + (hash >>> 0).toString(16).padStart(8, '0');
}

function canonicalTitle(listings: CatalogListing[]): string {
  // Prefer the richest title metadata, then deterministic lexical ordering.
  return [...listings].sort((a, b) =>
    (b.title.trim().length - a.title.trim().length) ||
    a.title.localeCompare(b.title) ||
    a.sourceKey.localeCompare(b.sourceKey),
  )[0]?.title ?? 'Untitled work';
}

/**
 * Groups source listings into likely underlying works.
 *
 * This is a candidate-grouping pass, not an unconditional merge of source records.
 * Exact titles alone are not enough; adaptations, same-name works and language
 * editions remain separate unless supported by strong evidence or user confirmation.
 * Pair comparisons are restricted to title/alias and external-ID blocks to avoid
 * quadratic comparisons across very large catalogs.
 */
export function groupCatalogListings(
  input: ProviderListing[],
  options: CatalogMergeOptions = {},
): CatalogGroup[] {
  const listings: CatalogListing[] = input.map((listing) => ({
    ...listing,
    sourceKey: sourceKey(listing),
    normalizedTitle: normalizeTitle(listing.title),
  }));
  const unique = new Map<string, CatalogListing>();
  for (const listing of listings) unique.set(listing.sourceKey, listing);
  const items = [...unique.values()].sort((a, b) => a.sourceKey.localeCompare(b.sourceKey));
  const parent = items.map((_, index) => index);
  const indexByKey = new Map(items.map((item, index) => [item.sourceKey, index]));
  const rejected = new Set((options.rejectedPairs ?? []).map(([a, b]) => pairKey(a, b)));
  const confirmed = new Set((options.confirmedPairs ?? []).map(([a, b]) => pairKey(a, b)));
  const confidenceByRoot = new Map<number, number>();
  const reviewByRoot = new Map<number, boolean>();

  const find = (value: number): number => {
    let root = value;
    while (parent[root] !== root) root = parent[root];
    while (parent[value] !== value) {
      const next = parent[value];
      parent[value] = root;
      value = next;
    }
    return root;
  };
  const union = (left: number, right: number, confidence: number, review: boolean) => {
    let a = find(left);
    let b = find(right);
    if (a === b) {
      confidenceByRoot.set(a, Math.max(confidenceByRoot.get(a) ?? 0, confidence));
      reviewByRoot.set(a, (reviewByRoot.get(a) ?? false) || review);
      return;
    }
    // Deterministic union root keeps output stable regardless of input order.
    if (a > b) [a, b] = [b, a];
    parent[b] = a;
    confidenceByRoot.set(a, Math.max(confidenceByRoot.get(a) ?? 0, confidenceByRoot.get(b) ?? 0, confidence));
    reviewByRoot.set(a, (reviewByRoot.get(a) ?? false) || (reviewByRoot.get(b) ?? false) || review);
  };

  const blocks = new Map<string, number[]>();
  const addBlock = (key: string, index: number) => {
    if (!key) return;
    const block = blocks.get(key) ?? [];
    block.push(index);
    blocks.set(key, block);
  };
  items.forEach((item, index) => {
    const titles = new Set([item.title, ...item.aliases].map(normalizeTitle).filter(Boolean));
    for (const title of titles) addBlock('t:' + title, index);
    for (const [namespace, id] of Object.entries(item.externalIds ?? {})) {
      if (namespace && id) addBlock('x:' + namespace + ':' + id, index);
    }
  });

  const compared = new Set<string>();
  for (const block of blocks.values()) {
    // Avoid pathological huge title blocks; compare exact external identifiers
    // separately and let ambiguous common titles be review candidates.
    if (block.length > 2000) continue;
    for (let i = 0; i < block.length; i += 1) {
      for (let j = i + 1; j < block.length; j += 1) {
        const leftIndex = block[i];
        const rightIndex = block[j];
        if (leftIndex === rightIndex) continue;
        const left = items[leftIndex];
        const right = items[rightIndex];
        const key = pairKey(left.sourceKey, right.sourceKey);
        if (compared.has(key) || rejected.has(key)) continue;
        compared.add(key);
        const manuallyConfirmed = confirmed.has(key);
        const assessment = assessWorkMatch(candidate(left), candidate(right));
        const sameCreatorName = creatorNames(left).some((name) => creatorNames(right).includes(name));
        const externalIdMatch = Object.entries(left.externalIds ?? {}).some(([namespace, id]) => Boolean(id) && right.externalIds?.[namespace] === id);
        const sameOriginalLanguage = !left.originalLanguage || !right.originalLanguage || left.originalLanguage === right.originalLanguage;
        const titleCompatible = normalizeTitle(left.title) === normalizeTitle(right.title) ||
          left.aliases.some((alias) => [right.title, ...right.aliases].some((other) => normalizeTitle(alias) === normalizeTitle(other)));
        const safeAutomaticMatch = externalIdMatch ||
          (assessment.autoMerge && sameOriginalLanguage) ||
          (titleCompatible && sameCreatorName && sameOriginalLanguage && assessment.confidence >= 0.9);
        if (manuallyConfirmed || safeAutomaticMatch) {
          union(leftIndex, rightIndex, manuallyConfirmed ? 1 : assessment.confidence, !manuallyConfirmed && !externalIdMatch && assessment.confidence < 0.95);
        } else if (assessment.confidence >= 0.5 || (titleCompatible && sameCreatorName)) {
          // Keep a visible review suggestion without silently merging the records.
          const root = find(leftIndex);
          reviewByRoot.set(root, true);
          confidenceByRoot.set(root, Math.max(confidenceByRoot.get(root) ?? 0, assessment.confidence));
        }
      }
    }
  }

  const groups = new Map<number, CatalogListing[]>();
  items.forEach((item, index) => {
    const root = find(index);
    const group = groups.get(root) ?? [];
    group.push(item);
    groups.set(root, group);
  });

  return [...groups.entries()].map(([root, groupListings]) => {
    const keys = groupListings.map((listing) => listing.sourceKey).sort();
    const id = stableId(keys);
    const aliases = [...new Set(groupListings.flatMap((listing) => [listing.title, ...listing.aliases]).map((title) => title.trim()).filter(Boolean))].sort((a, b) => a.localeCompare(b));
    const preferred = options.canonicalTitles?.[id]?.trim();
    return {
      id,
      canonicalTitle: preferred || canonicalTitle(groupListings),
      aliases,
      listings: groupListings.sort((a, b) => a.providerId.localeCompare(b.providerId) || a.title.localeCompare(b.title)),
      confidence: confidenceByRoot.get(root) ?? (groupListings.length > 1 ? 0.9 : 1),
      needsReview: reviewByRoot.get(root) ?? false,
    };
  }).sort((a, b) => a.canonicalTitle.localeCompare(b.canonicalTitle) || a.id.localeCompare(b.id));
}

export interface LatestChapterCandidate {
  listingId: string;
  providerId: string;
  chapter: ChapterListing;
}

/** Sorts source chapter candidates newest-first without pretending chapter labels are numbers. */
export function rankLatestChapterCandidates(candidates: LatestChapterCandidate[]): LatestChapterCandidate[] {
  const timestamp = (candidate: LatestChapterCandidate): number => {
    const value = candidate.chapter.publishedAt ?? candidate.chapter.lastVerifiedAt;
    const parsed = value ? Date.parse(value) : 0;
    return Number.isFinite(parsed) ? parsed : 0;
  };
  return [...candidates].sort((a, b) =>
    timestamp(b) - timestamp(a) ||
    (b.chapter.sortOrder ?? -1) - (a.chapter.sortOrder ?? -1) ||
    a.providerId.localeCompare(b.providerId) ||
    a.chapter.id.localeCompare(b.chapter.id),
  );
}
