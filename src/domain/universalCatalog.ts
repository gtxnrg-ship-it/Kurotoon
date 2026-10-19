import type {
  CreatorReference,
  ProviderListing,
  PublicationStatus,
} from './models';
import { normalizeTitle } from './identity';

export interface UniversalWorkGroup {
  /** Ephemeral search-result identity. Persistence should use a canonical Work.id. */
  id: string;
  canonicalTitle: string;
  aliases: string[];
  listings: ProviderListing[];
  providerIds: string[];
  creators: CreatorReference[];
  publicationStatus: PublicationStatus;
  /** Best source listing to use as the initial route into the series. */
  primaryListing: ProviderListing;
  /** Most recently verified source metadata; this is not the same as latest chapter release. */
  mostRecentlyVerifiedListing: ProviderListing;
}

function sourceKey(listing: ProviderListing): string {
  return listing.providerId + ':' + listing.providerWorkId;
}

function verifiedAt(listing: ProviderListing): number {
  if (!listing.lastVerifiedAt) return 0;
  const value = Date.parse(listing.lastVerifiedAt);
  return Number.isFinite(value) ? value : 0;
}

function creatorIdentityKeys(listing: ProviderListing): string[] {
  return [...new Set(listing.creators
    .map(creator => normalizeTitle(creator.name))
    .filter(Boolean)
    .map(name => 'creator:' + name))];
}

function externalIdentityKeys(listing: ProviderListing): string[] {
  return Object.entries(listing.externalIds ?? {})
    .map(([authority, id]) => {
      const namespace = authority.trim().toLocaleLowerCase();
      const value = id.trim().toLocaleLowerCase();
      return namespace && value ? 'external:' + namespace + ':' + value : '';
    })
    .filter(Boolean);
}

function fnv1a(value: string): string {
  let result = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    result ^= value.charCodeAt(index);
    result = Math.imul(result, 0x01000193);
  }
  return (result >>> 0).toString(16).padStart(8, '0');
}

class DisjointSet {
  private readonly parent: number[];
  private readonly rank: number[];

  constructor(size: number) {
    this.parent = Array.from({ length: size }, (_, index) => index);
    this.rank = new Array<number>(size).fill(0);
  }

  find(index: number): number {
    let current = index;
    while (this.parent[current] !== current) {
      this.parent[current] = this.parent[this.parent[current]];
      current = this.parent[current];
    }
    return current;
  }

  union(left: number, right: number): void {
    let a = this.find(left);
    let b = this.find(right);
    if (a === b) return;
    if (this.rank[a] < this.rank[b]) [a, b] = [b, a];
    this.parent[b] = a;
    if (this.rank[a] === this.rank[b]) this.rank[a] += 1;
  }
}

function addAlias(aliases: Map<string, string>, value: string): void {
  const label = value.trim();
  const key = normalizeTitle(label);
  if (key && label && !aliases.has(key)) aliases.set(key, label);
}

function canonicalTitleFor(listings: ProviderListing[]): string {
  // Vote by distinct providers, not raw result count, so one prolific provider
  // cannot dominate the canonical display name merely by returning duplicates.
  const votes = new Map<string, { label: string; providers: Set<string>; englishVotes: number }>();
  for (const listing of listings) {
    const label = listing.title.trim();
    const key = normalizeTitle(label);
    if (!key) continue;
    const vote = votes.get(key) ?? { label, providers: new Set<string>(), englishVotes: 0 };
    vote.providers.add(listing.providerId);
    if (listing.languageCode?.toLocaleLowerCase().startsWith('en')) vote.englishVotes += 1;
    if (label.length > vote.label.length) vote.label = label;
    votes.set(key, vote);
  }
  return [...votes.values()].sort((left, right) =>
    right.providers.size - left.providers.size ||
    right.englishVotes - left.englishVotes ||
    right.label.length - left.label.length ||
    normalizeTitle(left.label).localeCompare(normalizeTitle(right.label)),
  )[0]?.label ?? listings[0]?.title ?? 'Untitled series';
}

function creatorsFor(listings: ProviderListing[]): CreatorReference[] {
  const byIdentity = new Map<string, CreatorReference>();
  for (const listing of listings) {
    for (const creator of listing.creators) {
      const name = creator.name.trim();
      if (!name) continue;
      const key = normalizeTitle(name) + ':' + (creator.role ?? 'other');
      const current = byIdentity.get(key);
      if (!current || (!current.id && creator.id)) byIdentity.set(key, creator);
    }
  }
  return [...byIdentity.values()].sort((left, right) =>
    (left.role ?? '').localeCompare(right.role ?? '') || left.name.localeCompare(right.name),
  );
}

function statusFor(listings: ProviderListing[]): PublicationStatus {
  const votes = new Map<PublicationStatus, number>();
  for (const listing of listings) {
    if (listing.publicationStatus === 'unknown') continue;
    votes.set(listing.publicationStatus, (votes.get(listing.publicationStatus) ?? 0) + 1);
  }
  return [...votes.entries()].sort((left, right) =>
    right[1] - left[1] || left[0].localeCompare(right[0]),
  )[0]?.[0] ?? 'unknown';
}

function buildGroup(listingsInput: ProviderListing[]): UniversalWorkGroup {
  const listings = [...listingsInput].sort((left, right) =>
    verifiedAt(right) - verifiedAt(left) || left.providerId.localeCompare(right.providerId) ||
    left.providerWorkId.localeCompare(right.providerWorkId),
  );
  const aliases = new Map<string, string>();
  for (const listing of listings) {
    addAlias(aliases, listing.title);
    for (const alias of listing.aliases) addAlias(aliases, alias);
  }
  const canonicalTitle = canonicalTitleFor(listings);
  aliases.delete(normalizeTitle(canonicalTitle));
  const providerIds = [...new Set(listings.map(listing => listing.providerId))].sort();
  const primaryListing = listings.find(listing => listing.coverUrl) ?? listings[0];
  const mostRecentlyVerifiedListing = [...listings].sort((left, right) =>
    verifiedAt(right) - verifiedAt(left),
  )[0];

  return {
    id: 'work:' + fnv1a(listings.map(sourceKey).sort().join('|')),
    canonicalTitle,
    aliases: [...aliases.values()].slice(0, 250),
    listings,
    providerIds,
    creators: creatorsFor(listings),
    publicationStatus: statusFor(listings),
    primaryListing,
    mostRecentlyVerifiedListing,
  };
}

/**
 * Deduplicate source listings and group high-confidence representations of the
 * same underlying work. This is deliberately conservative: a title alone, a
 * shared creator alone, or fuzzy similarity never triggers an automatic merge.
 *
 * The indexed approach is near O(n alpha(n)) for ordinary provider output.
 * It avoids comparing every pair in a large same-title bucket. Work/edition
 * decisions are separate: language editions stay as listings under one Work.
 */
export function groupUniversalWorks(input: ProviderListing[]): UniversalWorkGroup[] {
  const unique = new Map<string, ProviderListing>();
  for (const listing of input) {
    if (!listing.providerId.trim() || !listing.providerWorkId.trim() || !listing.title.trim()) continue;
    const key = sourceKey(listing);
    const previous = unique.get(key);
    if (!previous || verifiedAt(listing) >= verifiedAt(previous)) unique.set(key, listing);
  }

  const listings = [...unique.values()];
  if (!listings.length) return [];
  const sets = new DisjointSet(listings.length);
  const externalIndex = new Map<string, number>();
  const titleCreatorIndex = new Map<string, number>();

  listings.forEach((listing, index) => {
    for (const externalKey of externalIdentityKeys(listing)) {
      const previous = externalIndex.get(externalKey);
      if (previous === undefined) externalIndex.set(externalKey, index);
      else sets.union(index, previous);
    }

    const title = normalizeTitle(listing.title);
    if (!title) return;
    for (const creatorKey of creatorIdentityKeys(listing)) {
      const matchKey = title + '\u0000' + creatorKey;
      const previous = titleCreatorIndex.get(matchKey);
      if (previous === undefined) titleCreatorIndex.set(matchKey, index);
      else sets.union(index, previous);
    }
  });

  const buckets = new Map<number, ProviderListing[]>();
  listings.forEach((listing, index) => {
    const root = sets.find(index);
    const bucket = buckets.get(root) ?? [];
    bucket.push(listing);
    buckets.set(root, bucket);
  });

  return [...buckets.values()]
    .map(buildGroup)
    .sort((left, right) =>
      normalizeTitle(left.canonicalTitle).localeCompare(normalizeTitle(right.canonicalTitle)) ||
      left.id.localeCompare(right.id),
    );
}
