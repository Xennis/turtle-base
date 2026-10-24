import { MemoryKeyValueStore } from '@turtle-base/platform/testing';
import { Hlc } from '@turtle-base/sql-crdt';
import { expect, test } from 'vite-plus/test';

import { KeyValueSyncStateStore } from './key-value-sync-state-store.ts';

test('keeps the state per node id across instances', async () => {
  const prefs = new MemoryKeyValueStore();
  const hlc = new Hlc(Date.parse('2026-10-24T12:00:00Z'), 3, 'a');
  await new KeyValueSyncStateStore(prefs).setLastPushedAt('a', hlc);
  await new KeyValueSyncStateStore(prefs).setMergedFiles('a', new Set(['b/1.json', 'c/2.json']));

  const restarted = new KeyValueSyncStateStore(prefs);

  expect(restarted.lastPushedAt('a')).toEqual(hlc);
  expect(restarted.mergedFiles('a')).toEqual(new Set(['b/1.json', 'c/2.json']));
  expect(restarted.lastPushedAt('other')).toBeUndefined();
  expect(restarted.mergedFiles('other')).toEqual(new Set());
});
