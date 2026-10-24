import type { KeyValueStore } from '@turtle-base/platform';
import { Hlc } from '@turtle-base/sql-crdt';

import type { SyncStateStore } from '../../packages/crdt-file-sync/sync-state-store.ts';

/** Persists {@link SyncStateStore} across app restarts in the device's prefs - per device, like the theme. */
export class KeyValueSyncStateStore implements SyncStateStore {
  readonly #prefs: KeyValueStore;

  constructor(prefs: KeyValueStore) {
    this.#prefs = prefs;
  }

  lastPushedAt(nodeId: string): Hlc | undefined {
    const stored = this.#prefs.get(lastPushedAtKey(nodeId));
    return stored === undefined ? undefined : Hlc.parse(stored);
  }

  setLastPushedAt(nodeId: string, hlc: Hlc): Promise<void> {
    return this.#prefs.set(lastPushedAtKey(nodeId), hlc.toString());
  }

  mergedFiles(nodeId: string): Set<string> {
    const stored = this.#prefs.get(mergedFilesKey(nodeId));
    if (stored === undefined) return new Set();
    const names: unknown = JSON.parse(stored);
    return new Set(Array.isArray(names) ? names.filter((name) => typeof name === 'string') : []);
  }

  setMergedFiles(nodeId: string, names: ReadonlySet<string>): Promise<void> {
    return this.#prefs.set(mergedFilesKey(nodeId), JSON.stringify([...names]));
  }
}

function lastPushedAtKey(nodeId: string): string {
  return `sync.${nodeId}.last_pushed_at`;
}

function mergedFilesKey(nodeId: string): string {
  return `sync.${nodeId}.merged_files`;
}
