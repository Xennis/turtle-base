import * as v from 'valibot';

export const folderMimeType = 'application/vnd.google-apps.folder';

const api = 'https://www.googleapis.com';

/** From this size on, uploads use Drive's resumable protocol instead of one multipart request (Drive's limit for those). */
export const resumableThreshold = 5 * 1024 * 1024;

export interface DriveFile {
  readonly id: string;
  readonly name: string;
}

const fileSchema = v.object({ id: v.string(), name: v.string() });
const pageSchema = v.object({ files: v.optional(v.array(fileSchema), []), nextPageToken: v.optional(v.string()) });
const createdSchema = v.object({ id: v.string() });

/** Drive answered with an error status. */
export class DriveError extends Error {
  override readonly name = 'DriveError';
  readonly status: number;

  constructor(status: number, detail: string) {
    super(`Google Drive answered ${status}: ${detail}`);
    this.status = status;
  }
}

/**
 * The few Drive REST calls the sync needs, on plain `fetch` - the official
 * client library is far too big for a web view. `accessToken` is asked for
 * every request, so the authenticator can refresh it.
 */
export class DriveClient {
  readonly #fetch: typeof fetch;
  readonly #accessToken: () => Promise<string>;

  constructor(options: { fetch: typeof fetch; accessToken: () => Promise<string> }) {
    this.#fetch = options.fetch;
    this.#accessToken = options.accessToken;
  }

  /** Every file matching `query` - Drive returns one page per call, so this follows `nextPageToken`. */
  async listAll(query: string): Promise<DriveFile[]> {
    const files: DriveFile[] = [];
    let pageToken: string | undefined;
    do {
      const url = new URL(`${api}/drive/v3/files`);
      url.search = new URLSearchParams({
        q: query,
        spaces: 'drive',
        pageSize: '1000',
        fields: 'nextPageToken,files(id,name)',
        ...(pageToken === undefined ? {} : { pageToken }),
      }).toString();
      const page = v.parse(pageSchema, await (await this.#request(url)).json());
      files.push(...page.files);
      pageToken = page.nextPageToken;
    } while (pageToken !== undefined);
    return files;
  }

  async createFolder(name: string, parentId: string | undefined): Promise<string> {
    const response = await this.#request(new URL(`${api}/drive/v3/files`), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify({
        name,
        mimeType: folderMimeType,
        ...(parentId === undefined ? {} : { parents: [parentId] }),
      }),
    });
    return v.parse(createdSchema, await response.json()).id;
  }

  /** Creates a file with `content` in `parentId` and returns its id. */
  async createFile(name: string, parentId: string, content: Blob): Promise<string> {
    const metadata = JSON.stringify({ name, parents: [parentId] });
    if (content.size >= resumableThreshold) {
      const session = await this.#request(new URL(`${api}/upload/drive/v3/files?uploadType=resumable`), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8', 'X-Upload-Content-Length': String(content.size) },
        body: metadata,
      });
      const location = session.headers.get('Location');
      if (location === null) throw new DriveError(session.status, 'no upload session');
      const uploaded = await this.#request(new URL(location), { method: 'PUT', body: content });
      return v.parse(createdSchema, await uploaded.json()).id;
    }
    const boundary = `turtle-base-${crypto.randomUUID()}`;
    const body = new Blob([
      `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${metadata}\r\n`,
      `--${boundary}\r\nContent-Type: application/octet-stream\r\n\r\n`,
      content,
      `\r\n--${boundary}--`,
    ]);
    const response = await this.#request(new URL(`${api}/upload/drive/v3/files?uploadType=multipart`), {
      method: 'POST',
      headers: { 'Content-Type': `multipart/related; boundary=${boundary}` },
      body,
    });
    return v.parse(createdSchema, await response.json()).id;
  }

  /** Replaces the content of file `id`. */
  async updateFile(id: string, content: Blob): Promise<void> {
    await this.#request(new URL(`${api}/upload/drive/v3/files/${encodeURIComponent(id)}?uploadType=media`), {
      method: 'PATCH',
      body: content,
    });
  }

  async download(id: string): Promise<ReadableStream<Uint8Array>> {
    const response = await this.#request(new URL(`${api}/drive/v3/files/${encodeURIComponent(id)}?alt=media`));
    if (response.body === null) throw new DriveError(response.status, 'empty body');
    return response.body;
  }

  async #request(url: URL, init: RequestInit = {}): Promise<Response> {
    const headers = new Headers(init.headers);
    headers.set('Authorization', `Bearer ${await this.#accessToken()}`);
    const response = await this.#fetch(url, { ...init, headers });
    if (!response.ok) throw new DriveError(response.status, await response.text());
    return response;
  }
}

/** Escapes `value` for a string literal in a Drive query. */
export function escapeQuery(value: string): string {
  return value.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
}
