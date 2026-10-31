/**
 * One flat directory of the app's own files (e.g. attachments), by name.
 * Writing goes through a temporary file that only gets its name once
 * complete - so a file under its final name is always whole, and the name
 * can depend on the content (e.g. its hash).
 */
export interface FileDirectory {
  /** The names of the files present, temporary ones excluded. */
  list(): Promise<string[]>;
  exists(name: string): Promise<boolean>;

  /** In bytes. */
  size(name: string): Promise<number>;
  read(name: string): Promise<ReadableStream<Uint8Array>>;

  /** The first `length` bytes, e.g. to detect the file type. */
  readHead(name: string, length: number): Promise<Uint8Array>;

  /** Writes `bytes` to a new temporary file and returns its handle. */
  writeTemp(bytes: ReadableStream<Uint8Array>): Promise<string>;

  /** Gives a temporary file its final name, replacing a file of that name. */
  commitTemp(handle: string, name: string): Promise<void>;
  discardTemp(handle: string): Promise<void>;

  /** Deletes a file - nothing happens if it's not there. */
  remove(name: string): Promise<void>;

  /** A URL the web view can load the file from, e.g. for an `<img>`. */
  urlOf(name: string): string;
}
