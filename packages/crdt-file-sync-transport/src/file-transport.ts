/**
 * Flat storage for content-addressed files (images, attachments) that
 * `FileSyncController` shares between devices.
 *
 * Streamed rather than `Uint8Array`-based like `SyncTransport`, since files
 * can be far larger than a changeset. Names are chosen by the caller and
 * unique per content, so uploading a name that already exists is harmless.
 */
export interface FileTransport {
  /** Uploads `length` bytes from `bytes` under `name`. */
  upload(name: string, bytes: ReadableStream<Uint8Array>, length: number): Promise<void>;

  /** The names of all files currently stored. */
  list(): Promise<Set<string>>;

  /** Streams the file previously uploaded as `name`. */
  download(name: string): Promise<ReadableStream<Uint8Array>>;
}
