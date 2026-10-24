import type { SyncTransport } from '@turtle-base/crdt-file-sync-transport';
import { parseChangeset, recordCount, type Crdt, type Hlc } from '@turtle-base/sql-crdt';

import { Notifier } from '../../core/notifier.ts';
import { InMemorySyncStateStore, type SyncStateStore } from './sync-state-store.ts';

export type SyncStatus = 'idle' | 'syncing' | 'error';

/**
 * Push/pull/merge engine that keeps a local {@link Crdt} in sync with others
 * through an opaque {@link SyncTransport}.
 *
 * Every device pushes its own changesets under a folder-like prefix named
 * after its node id, and pulls and merges every other device's prefix.
 * Merging is idempotent, so re-downloading a file that was already merged is
 * wasted bandwidth but never wrong. What was pushed survives restarts through
 * {@link SyncStateStore}, see `.local/SYNC_COMPACTION.md`.
 *
 * `syncNow()` is the only entry point, so a background trigger (timer, app
 * lifecycle) can call the exact same method a "sync now" button uses.
 */
export class SyncController<DB> extends Notifier {
  readonly #crdt: Crdt<DB>;
  readonly #transport: SyncTransport;
  readonly #state: SyncStateStore;

  status: SyncStatus = 'idle';
  lastSyncedAt: Date | undefined;
  lastError: unknown;

  constructor(crdt: Crdt<DB>, transport: SyncTransport, state: SyncStateStore = new InMemorySyncStateStore()) {
    super();
    this.#crdt = crdt;
    this.#transport = transport;
    this.#state = state;
  }

  async syncNow(): Promise<void> {
    this.status = 'syncing';
    this.lastError = undefined;
    this.notify();
    try {
      // Listed once, before pushing - the pull skips own files anyway.
      const names = await this.#transport.list();
      await this.#push(names);
      await this.#pull(names);
      this.status = 'idle';
      this.lastSyncedAt = new Date();
    } catch (error) {
      console.warn('[sync] syncNow() failed:', error);
      this.status = 'error';
      this.lastError = error;
    }
    this.notify();
  }

  /**
   * Uploads own changes since the last push - or everything, when `listed`
   * has no own file (first sync, or the own folder was removed or moved),
   * since then nothing pushed before is still there.
   */
  async #push(listed: readonly string[]): Promise<void> {
    const nodeId = this.#crdt.nodeId;
    const hasOwnFile = listed.some((name) => name.startsWith(`${nodeId}/`));
    const since = hasOwnFile ? this.#state.lastPushedAt(nodeId) : undefined;

    // `onlyNodeId` matters beyond saving bandwidth: merged rows carry this
    // node's `modified`, so a plain time filter would pick up rows just pulled
    // from someone else and re-upload them under our own name.
    const changeset = await this.#crdt.getChangeset({ onlyNodeId: nodeId, modifiedAfter: since });
    const pushedAt = await this.#crdt.getLastModified({ onlyNodeId: nodeId });
    if (recordCount(changeset) === 0 || pushedAt === undefined) return;

    await this.#transport.upload(
      `${nodeId}/${fileNameFor(pushedAt)}`,
      new TextEncoder().encode(JSON.stringify(changeset)),
    );
    // Only after the upload - a failure in between means uploading again, never losing a change.
    await this.#state.setLastPushedAt(nodeId, pushedAt);
  }

  /**
   * Downloads and merges the listed files of other devices not merged before.
   * Changeset files never change and merging is order independent, so
   * remembering the merged names is all it takes. A file that fails stays
   * unmerged and is retried on the next sync, without holding up the others.
   */
  async #pull(names: readonly string[]): Promise<void> {
    const nodeId = this.#crdt.nodeId;
    // Names no longer listed (deleted on the remote) are dropped, so the set doesn't grow forever.
    const remembered = this.#state.mergedFiles(nodeId);
    const merged = new Set([...remembered].filter((name) => names.includes(name)));
    if (merged.size !== remembered.size) await this.#state.setMergedFiles(nodeId, merged);

    const pending = names.filter((name) => {
      const owner = nodeIdOf(name);
      return owner !== undefined && owner !== nodeId && !merged.has(name);
    });
    const failures = new Map<string, unknown>();
    for (const name of pending) {
      try {
        const bytes = await this.#transport.download(name);
        await this.#crdt.merge(parseChangeset(JSON.parse(new TextDecoder().decode(bytes))));
        merged.add(name);
        // After each merge - a crash later only means merging this one again, which is harmless.
        await this.#state.setMergedFiles(nodeId, merged);
      } catch (error) {
        failures.set(name, error);
      }
    }
    if (failures.size > 0) throw new ChangesetPullError(failures);
  }
}

/** The device a `<nodeId>/<file>` name belongs to, undefined for other names. */
function nodeIdOf(name: string): string | undefined {
  const slash = name.indexOf('/');
  return slash === -1 ? undefined : name.slice(0, slash);
}

/** A filename-safe, sortable name for `hlc` - not its string form, whose `:` isn't safe on every transport. */
function fileNameFor(hlc: Hlc): string {
  return `${hlc.millis}-${hlc.counter}.json`;
}

/** Some changesets couldn't be downloaded or merged - the others were, and these are retried on the next sync. */
export class ChangesetPullError extends Error {
  override readonly name = 'ChangesetPullError';
  readonly failures: ReadonlyMap<string, unknown>;

  constructor(failures: ReadonlyMap<string, unknown>) {
    const count = failures.size === 1 ? '1 changeset' : `${failures.size} changesets`;
    super(`${count} could not be merged, retried on the next sync`, { cause: [...failures.values()][0] });
    this.failures = failures;
  }
}
