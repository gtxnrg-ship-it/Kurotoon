import { describe, expect, it } from 'vitest';
import { createSeededRandom } from './random';

describe('createSeededRandom', () => {
  it('produces the same sequence for the same seed', () => {
    const first = createSeededRandom(12345);
    const second = createSeededRandom(12345);
    expect(Array.from({ length: 32 }, first)).toEqual(Array.from({ length: 32 }, second));
  });

  it('produces values in the half-open interval [0, 1)', () => {
    const random = createSeededRandom(0xffffffff);
    for (let i = 0; i < 1000; i++) {
      const value = random();
      expect(value).toBeGreaterThanOrEqual(0);
      expect(value).toBeLessThan(1);
    }
  });

  it('changes its sequence when the seed changes', () => {
    const first = createSeededRandom(1);
    const second = createSeededRandom(2);
    expect(Array.from({ length: 8 }, first)).not.toEqual(Array.from({ length: 8 }, second));
  });
});
