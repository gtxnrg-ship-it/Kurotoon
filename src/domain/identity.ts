import type { Work } from './models';

export interface WorkIdentityCandidate {
  title: string;
  aliases?: string[];
  creatorIds?: string[];
  externalIds?: Record<string, string>;
}

export interface WorkMatchAssessment {
  confidence: number;
  autoMerge: boolean;
  reasons: string[];
}

function normalized(value: string): string {
  return value
    .normalize('NFKC')
    .toLocaleLowerCase()
    .replace(/[’']/g, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function titleSet(candidate: WorkIdentityCandidate): Set<string> {
  return new Set([candidate.title, ...(candidate.aliases ?? [])].map(normalized).filter(Boolean));
}

function sharedValues(left: string[] = [], right: string[] = []): string[] {
  const rightSet = new Set(right.filter(Boolean));
  return [...new Set(left.filter(Boolean))].filter(value => rightSet.has(value));
}

function hasMatchingExternalId(left: Record<string, string> = {}, right: Record<string, string> = {}): boolean {
  return Object.entries(left).some(([namespace, id]) => Boolean(id) && right[namespace] === id);
}

export function normalizeTitle(value: string): string {
  return normalized(value);
}

/**
 * Scores whether two listings describe the same underlying work.
 * This does not merge editions or translations; those remain separate records.
 * Exact title alone is deliberately insufficient for automatic merging.
 */
export function assessWorkMatch(
  left: WorkIdentityCandidate | Pick<Work, 'canonicalTitle' | 'aliases' | 'creatorIds'>,
  right: WorkIdentityCandidate | Pick<Work, 'canonicalTitle' | 'aliases' | 'creatorIds'>,
): WorkMatchAssessment {
  const a: WorkIdentityCandidate = 'canonicalTitle' in left
    ? { title: left.canonicalTitle, aliases: left.aliases, creatorIds: left.creatorIds }
    : left;
  const b: WorkIdentityCandidate = 'canonicalTitle' in right
    ? { title: right.canonicalTitle, aliases: right.aliases, creatorIds: right.creatorIds }
    : right;

  const reasons: string[] = [];
  if (hasMatchingExternalId(a.externalIds, b.externalIds)) {
    return { confidence: 0.99, autoMerge: true, reasons: ['matching external identifier'] };
  }

  const aTitles = titleSet(a);
  const bTitles = titleSet(b);
  const primaryTitleMatches = normalized(a.title) !== '' && normalized(a.title) === normalized(b.title);
  const aliasOrTitleOverlap = [...aTitles].some(title => bTitles.has(title));
  const creatorsOverlap = sharedValues(a.creatorIds, b.creatorIds).length > 0;

  let confidence = 0.05;
  if (primaryTitleMatches) {
    confidence += 0.65;
    reasons.push('normalized primary titles match');
  } else if (aliasOrTitleOverlap) {
    confidence += 0.5;
    reasons.push('title or alias overlaps');
  }
  if (creatorsOverlap) {
    confidence += 0.25;
    reasons.push('at least one creator identifier matches');
  }

  confidence = Math.min(confidence, 0.95);
  const autoMerge = primaryTitleMatches && creatorsOverlap && confidence >= 0.9;
  if (!reasons.length) reasons.push('no strong identity evidence');
  return { confidence, autoMerge, reasons };
}