import { describe, expect, test } from 'vite-plus/test';

import { ClockDriftError, DuplicateNodeError, Hlc, OverflowError } from './hlc.ts';

const t0 = Date.parse('2026-10-24T12:00:00.000Z');

describe('string form', () => {
  test('round-trips through parse', () => {
    const hlc = new Hlc(t0 + 5, 0x1a, 'node-1-with-dashes');

    expect(hlc.toString()).toBe('2026-10-24T12:00:00.005Z-001A-node-1-with-dashes');
    expect(Hlc.parse(hlc.toString())).toEqual(hlc);
  });

  test('orders like compare', () => {
    const hlcs = [
      new Hlc(t0, 2, 'a'),
      new Hlc(t0 + 1, 0, 'a'),
      new Hlc(t0, 0, 'b'),
      new Hlc(t0, 0x10, 'a'),
      new Hlc(0, 0, 'z'),
      new Hlc(t0, 0, 'a'),
    ];

    const byCompare = hlcs.toSorted((a, b) => a.compare(b)).map(String);
    const byString = hlcs.map(String).toSorted();
    expect(byString).toEqual(byCompare);
  });

  test('rejects anything else', () => {
    expect(() => Hlc.parse('2026-10-24T12:00:00Z-0000-a')).toThrow(SyntaxError);
    expect(() => Hlc.parse('not an hlc')).toThrow(SyntaxError);
  });
});

describe('increment', () => {
  test('takes the wall time when it advanced', () => {
    expect(new Hlc(t0, 3, 'a').increment(t0 + 1)).toEqual(new Hlc(t0 + 1, 0, 'a'));
  });

  test('counts up when the wall time did not advance', () => {
    expect(new Hlc(t0, 3, 'a').increment(t0)).toEqual(new Hlc(t0, 4, 'a'));
    expect(new Hlc(t0, 3, 'a').increment(t0 - 10)).toEqual(new Hlc(t0, 4, 'a'));
  });

  test('throws on too much drift', () => {
    expect(() => new Hlc(t0 + 60_001, 0, 'a').increment(t0)).toThrow(ClockDriftError);
  });

  test('throws on counter overflow', () => {
    expect(() => new Hlc(t0, 0xffff, 'a').increment(t0)).toThrow(OverflowError);
  });
});

describe('merge', () => {
  const local = new Hlc(t0, 5, 'local');

  test('keeps the local time when it is ahead', () => {
    expect(local.merge(new Hlc(t0 - 1, 9, 'remote'), t0)).toBe(local);
    expect(local.merge(new Hlc(t0, 5, 'remote'), t0)).toBe(local);
  });

  test('takes the remote time with the local node id', () => {
    expect(local.merge(new Hlc(t0, 6, 'remote'), t0)).toEqual(new Hlc(t0, 6, 'local'));
    expect(local.merge(new Hlc(t0 + 10, 0, 'remote'), t0)).toEqual(new Hlc(t0 + 10, 0, 'local'));
  });

  test('throws on a newer timestamp from the own node', () => {
    expect(() => local.merge(new Hlc(t0 + 1, 0, 'local'), t0)).toThrow(DuplicateNodeError);
  });

  test('throws on too much remote drift', () => {
    expect(() => local.merge(new Hlc(t0 + 60_001, 0, 'remote'), t0)).toThrow(ClockDriftError);
  });
});
