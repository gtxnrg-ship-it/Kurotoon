import { describe, expect, it } from 'vitest';
import { assessWorkMatch, normalizeTitle } from './identity';

describe('normalizeTitle', () => {
  it('normalizes case, punctuation, and spacing', () => {
    expect(normalizeTitle('  The  GREAT—Story! ')).toBe('the great story');
  });

  it('normalizes compatible Unicode forms', () => {
    expect(normalizeTitle('ＣＯＭＩＣ')).toBe('comic');
  });
});

describe('assessWorkMatch', () => {
  it('auto-matches exact normalized titles with shared creator evidence', () => {
    const assessment = assessWorkMatch(
      { title: 'The Moon Keeper', creatorIds: ['creator-1'] },
      { title: 'the moon keeper!', creatorIds: ['creator-1'] },
    );
    expect(assessment.confidence).toBe(0.95);
    expect(assessment.autoMerge).toBe(true);
  });

  it('normalizes optional leading English articles when creator identity also matches', () => {
    const assessment = assessWorkMatch(
      { title: 'The Moon Keeper', creatorIds: ['creator-1'] },
      { title: 'Moon Keeper!', creatorIds: ['creator-1'] },
    );
    expect(assessment.autoMerge).toBe(true);
    expect(assessment.confidence).toBe(0.95);
  });

  it('does not auto-merge based on title alone', () => {
    const assessment = assessWorkMatch(
      { title: 'Rebirth', creatorIds: [] },
      { title: 'Rebirth', creatorIds: [] },
    );
    expect(assessment.autoMerge).toBe(false);
    expect(assessment.confidence).toBe(0.7);
  });

  it('uses matching external IDs as strong identity evidence', () => {
    const assessment = assessWorkMatch(
      { title: 'Different local title', externalIds: { mal: '1234' } },
      { title: 'Translated title', externalIds: { mal: '1234' } },
    );
    expect(assessment.autoMerge).toBe(true);
    expect(assessment.confidence).toBe(0.99);
  });

  it('does not auto-merge unrelated titles just because creators overlap', () => {
    const assessment = assessWorkMatch(
      { title: 'Blue Morning', creatorIds: ['creator-1'] },
      { title: 'Red Evening', creatorIds: ['creator-1'] },
    );
    expect(assessment.autoMerge).toBe(false);
    expect(assessment.confidence).toBe(0.3);
  });

  it('matches a primary title to a known alias but keeps the decision conservative', () => {
    const assessment = assessWorkMatch(
      { title: 'Moon Keeper', creatorIds: [] },
      { title: 'Tsuki no Mamori', aliases: ['Moon Keeper'], creatorIds: [] },
    );
    expect(assessment.autoMerge).toBe(false);
    expect(assessment.reasons).toContain('title or alias overlaps');
  });
});