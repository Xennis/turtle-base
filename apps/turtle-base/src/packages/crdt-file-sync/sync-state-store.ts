import type { Hlc } from '@turtle-base/sql-crdt';

/**
 * What {@link SyncController} remembers between syncs - device-local, never
 * synced itself. Not a table: every table behind the CRDT database would be
 * part of the changesets.
 *
 * Keyed by the CRDT node id, so a reset database (new node id) starts from
 * scratch instead of trusting another database's state.
 */
export interface SyncStateStore {
  /** The newest own change already uploaded. */
  lastPushedAt(nodeId: string): Hlc | undefined;
  setLastPushedAt(nodeId: string, hlc: Hlc): Promise<void>;

  /** Names of other devices' changeset files already merged. */
  mergedFiles(nodeId: string): Set<string>;
  setMergedFiles(nodeId: string, names: ReadonlySet<string>): Promise<void>;
}

/** Forgets everything on restart - for tests, and as the default when nothing persists the state. */
export class InMemorySyncStateStore implements SyncStateStore {
  readonly #lastPushedAt = new Map<string, Hlc>();
  readonly #mergedFiles = new Map<string, Set<string>>();

  lastPushedAt(nodeId: string): Hlc | undefined {
    return this.#lastPushedAt.get(nodeId);
  }

  setLastPushedAt(nodeId: string, hlc: Hlc): Promise<void> {
    this.#lastPushedAt.set(nodeId, hlc);
    return Promise.resolve();
  }

  mergedFiles(nodeId: string): Set<string> {
    return new Set(this.#mergedFiles.get(nodeId));
  }

  setMergedFiles(nodeId: string, names: ReadonlySet<string>): Promise<void> {
    this.#mergedFiles.set(nodeId, new Set(names));
    return Promise.resolve();
  }
}
