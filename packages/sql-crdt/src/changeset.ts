import * as v from 'valibot';

/** A row as it travels between devices: column name to value, `hlc` included. */
export type CrdtRecord = Readonly<Record<string, string | number | null>>;

/**
 * Rows by table name - what one device hands another. JSON as is, so it can
 * be written to a file and read back.
 */
export type Changeset = Readonly<Record<string, readonly CrdtRecord[]>>;

const changesetSchema = v.record(
  v.string(),
  v.array(v.record(v.string(), v.union([v.string(), v.number(), v.null()]))),
);

/** Checks the shape of a changeset read from elsewhere, e.g. a downloaded file. */
export function parseChangeset(json: unknown): Changeset {
  const result = v.safeParse(changesetSchema, json);
  if (!result.success) throw new MergeError(`Not a changeset: ${v.summarize(result.issues)}`);
  return result.output;
}

export function recordCount(changeset: Changeset): number {
  return Object.values(changeset).reduce((count, records) => count + records.length, 0);
}

/** A changeset that can't be merged; nothing of it was. */
export class MergeError extends Error {
  override readonly name = 'MergeError';
}
