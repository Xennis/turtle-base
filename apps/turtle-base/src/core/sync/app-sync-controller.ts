import { GoogleDriveSyncFolder } from '@turtle-base/crdt-file-sync-google-drive';
import type { GoogleAuthenticator, KeyValueStore } from '@turtle-base/platform';
import type { Crdt } from '@turtle-base/sql-crdt';

import type { AttachmentsRepository } from '../../features/files/data/attachments-repository.ts';
import { FileSyncController } from '../../packages/crdt-file-sync/file-sync-controller.ts';
import { SyncController, type SyncStatus } from '../../packages/crdt-file-sync/sync-controller.ts';
import type { FileStore } from '../../packages/file-store/file-store.ts';
import type { Database } from '../database/schema.ts';
import { Notifier } from '../notifier.ts';
import { KeyValueSyncStateStore } from './key-value-sync-state-store.ts';
import { ensureSyncFormat } from './sync-format.ts';

const keepAllFilesOfflineKey = 'keep_all_files_offline';

/**
 * The Drive folder synced into. Not the Flutter app's `turtle-base-sync`:
 * syncing there would move its format to 3, and the Flutter app would stop
 * syncing on every device that still runs it.
 */
export const syncFolderName = 'turtle-base-sync-v3';

interface Connection {
  readonly folder: GoogleDriveSyncFolder;
  readonly sync: SyncController<Database>;
  readonly fileSync: FileSyncController;
  readonly unsubscribe: () => void;
}

/**
 * Owns the connect/disconnect lifecycle of Google Drive sync and the
 * {@link SyncController} and {@link FileSyncController} it produces once
 * connected - the one place that wires the transport-agnostic sync up with
 * this app's sign-in, CRDT and attachments (see `.local/FILES.md`).
 */
export class AppSyncController extends Notifier {
  readonly #crdt: Crdt<Database>;
  readonly #auth: GoogleAuthenticator | undefined;
  readonly #fetch: typeof fetch;
  readonly #files: FileStore;
  readonly #attachments: AttachmentsRepository;
  readonly #prefs: KeyValueStore;
  readonly #isMobile: boolean;
  readonly #folderName: string;
  #connection: Connection | undefined;

  /** Set when the last sync failed outside SyncController - e.g. a too new format, or listing the files folder. */
  #error: unknown;

  /** While files are uploaded or downloaded around SyncController's own run. */
  #syncingFiles = false;
  #failedFileCount = 0;

  constructor(options: {
    crdt: Crdt<Database>;
    auth: GoogleAuthenticator | undefined;
    fetch: typeof fetch;
    files: FileStore;
    attachments: AttachmentsRepository;
    prefs: KeyValueStore;
    isMobile: boolean;
    folderName?: string;
  }) {
    super();
    this.#crdt = options.crdt;
    this.#auth = options.auth;
    this.#fetch = options.fetch;
    this.#files = options.files;
    this.#attachments = options.attachments;
    this.#prefs = options.prefs;
    this.#isMobile = options.isMobile;
    this.#folderName = options.folderName ?? syncFolderName;
  }

  /** Whether sign-in is configured on this platform - false hides the Drive sync UI entirely. */
  get isAvailable(): boolean {
    return this.#auth !== undefined;
  }

  get isConnected(): boolean {
    return this.#connection !== undefined;
  }

  get status(): SyncStatus {
    if (this.#error !== undefined) return 'error';
    if (this.#syncingFiles) return 'syncing';
    return this.#connection?.sync.status ?? 'idle';
  }

  get lastSyncedAt(): Date | undefined {
    return this.#connection?.sync.lastSyncedAt;
  }

  get lastError(): unknown {
    return this.#error ?? this.#connection?.sync.lastError;
  }

  /** Files the last sync couldn't upload or download - retried next time. */
  get failedFileCount(): number {
    return this.#failedFileCount;
  }

  /**
   * Per device, not synced: download every file's original on sync rather
   * than only when it's opened. On by default on desktop, where storage is
   * rarely the constraint, off on mobile.
   */
  get keepAllFilesOffline(): boolean {
    const stored = this.#prefs.get(keepAllFilesOfflineKey);
    return stored === undefined ? !this.#isMobile : stored === 'true';
  }

  async setKeepAllFilesOffline(value: boolean): Promise<void> {
    await this.#prefs.set(keepAllFilesOfflineKey, String(value));
    this.notify();
  }

  /** Restores a previous connection without prompting - call once at app start. */
  async restoreConnection(): Promise<void> {
    if (this.#auth !== undefined && (await this.#auth.signInSilently())) this.#attach(this.#auth);
  }

  /** Prompts the user through the consent flow. Only offered when {@link isAvailable}. */
  async connect(): Promise<void> {
    const auth = this.#auth;
    if (auth === undefined) throw new Error('Drive sync is not available on this platform');
    await auth.signIn();
    this.#attach(auth);
  }

  async disconnect(): Promise<void> {
    await this.#auth?.signOut();
    this.#connection?.unsubscribe();
    this.#connection = undefined;
    this.#error = undefined;
    this.notify();
  }

  /**
   * Format check, then files up, changesets, files down - uploading files
   * before the changesets referencing them, so another device rarely sees an
   * attachment whose file isn't there yet. The format is checked on every
   * sync - another device may have bumped it since.
   */
  async syncNow(): Promise<void> {
    const connection = this.#connection;
    if (connection === undefined) return;
    const { folder, sync, fileSync } = connection;
    this.#error = undefined;
    this.#syncingFiles = true;
    this.notify();
    try {
      await ensureSyncFormat({
        read: () => folder.readFormatVersion(),
        write: (version) => folder.writeFormatVersion(version),
      });
      // Deleted attachments too - they can be restored.
      let failed = await fileSync.push(await this.#attachments.fileHashes(false));
      await sync.syncNow();
      if (sync.status !== 'error') {
        failed += await fileSync.pull(await this.#attachments.fileHashes(true), this.keepAllFilesOffline);
      }
      this.#failedFileCount = failed;
    } catch (error) {
      console.warn('[sync] syncNow() failed:', error);
      this.#error = error;
    } finally {
      this.#syncingFiles = false;
      this.notify();
    }
  }

  /** Downloads a file the store doesn't have yet, e.g. an original when it's opened. False when not connected or it failed. */
  async fetchFile(name: string): Promise<boolean> {
    if (await this.#files.has(name)) return true;
    return (await this.#connection?.fileSync.fetch(name)) ?? false;
  }

  #attach(auth: GoogleAuthenticator): void {
    this.#connection?.unsubscribe();
    const folder = new GoogleDriveSyncFolder({
      fetch: this.#fetch,
      accessToken: () => auth.accessToken(),
      name: this.#folderName,
    });
    const sync = new SyncController(this.#crdt, folder.changesets, new KeyValueSyncStateStore(this.#prefs));
    this.#connection = {
      folder,
      sync,
      fileSync: new FileSyncController(this.#files, folder.files),
      unsubscribe: sync.subscribe(() => this.notify()),
    };
    this.#error = undefined;
    this.notify();
  }
}
