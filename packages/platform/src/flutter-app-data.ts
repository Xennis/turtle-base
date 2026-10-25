import type { SqlRow } from './sql-driver.ts';

/**
 * The Flutter app's data on this device, read-only - what the one-time
 * import takes over: its SQLite database and its content-addressed files.
 */
export interface FlutterAppData {
  /** Where it was found, to show the user. */
  readonly location: string;

  /** The rows of a SELECT on the Flutter app's database. */
  query(sql: string): Promise<readonly SqlRow[]>;

  /** The names in its files folder - originals and thumbnails. */
  listFiles(): Promise<string[]>;

  readFile(name: string): Promise<ReadableStream<Uint8Array>>;
}
