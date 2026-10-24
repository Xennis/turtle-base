/**
 * The sync data layout this app version reads and writes. Bump it whenever
 * older app versions can no longer handle what this one syncs (folder
 * layout, a new table in the changesets, ...) - they then stop syncing with a
 * hint to update instead of failing on unknown data.
 *
 * 1 was the flat layout without a format file, 2 added the changesets/ and
 * files/ folders and the attachments table (both Flutter), 3 is the
 * TypeScript app's: no `is_deleted` column, millisecond timestamps.
 */
export const syncFormatVersion = 3;

export class SyncFormatTooNewError extends Error {
  override readonly name = 'SyncFormatTooNewError';
  readonly found: number;

  constructor(found: number) {
    super(
      `Sync data was written by a newer app version (format ${found}, this app supports ${syncFormatVersion}) - update the app.`,
    );
    this.found = found;
  }
}

/** Writes {@link syncFormatVersion} where there is none yet (or an older one), throws for a newer one. */
export async function ensureSyncFormat(io: {
  read: () => Promise<number | undefined>;
  write: (version: number) => Promise<void>;
}): Promise<void> {
  const found = await io.read();
  if (found !== undefined && found > syncFormatVersion) throw new SyncFormatTooNewError(found);
  if (found !== syncFormatVersion) await io.write(syncFormatVersion);
}
