import { folderMimeType } from './drive-client.ts';

interface FakeDriveFile {
  readonly id: string;
  readonly name: string;
  readonly mimeType: string;
  readonly parents: readonly string[];
  bytes: Uint8Array;
}

/**
 * A minimal in-memory stand-in for the Drive REST API - just enough to
 * exercise folder lookup and creation, paged listing, multipart and
 * resumable uploads, updates and downloads. Pass {@link fetch} where a
 * `fetch` goes.
 */
export class FakeDrive {
  readonly #files = new Map<string, FakeDriveFile>();
  readonly #sessions = new Map<string, { name: string; parents: string[] }>();
  readonly #maxPageSize: number;
  #nextId = 0;

  /** `maxPageSize` caps a page below the requested size, to exercise paging without a thousand files. */
  constructor(maxPageSize = 1000) {
    this.#maxPageSize = maxPageSize;
  }

  get folders(): FakeDriveFile[] {
    return [...this.#files.values()].filter((file) => file.mimeType === folderMimeType);
  }

  folderAt(path: readonly string[]): FakeDriveFile {
    let parent: FakeDriveFile | undefined;
    for (const name of path) {
      const found = this.folders.filter(
        (f) => f.name === name && (parent === undefined || f.parents.includes(parent.id)),
      );
      if (found.length !== 1) throw new Error(`No single folder ${path.join('/')}`);
      parent = found[0];
    }
    if (parent === undefined) throw new RangeError('Empty path');
    return parent;
  }

  filesIn(folder: FakeDriveFile): FakeDriveFile[] {
    return [...this.#files.values()].filter((file) => file.parents.includes(folder.id));
  }

  readonly fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    const path = url.pathname;
    if (request.headers.get('Authorization') !== 'Bearer token') return new Response('unauthorized', { status: 401 });
    if (request.method === 'GET' && path === '/drive/v3/files') return this.#list(url);
    if (request.method === 'GET' && path.startsWith('/drive/v3/files/')) return this.#download(path.slice(16));
    if (request.method === 'POST' && path === '/drive/v3/files')
      return this.#create(await request.json(), new Uint8Array());
    if (request.method === 'POST' && path === '/upload/drive/v3/files') {
      const body = new Uint8Array(await request.arrayBuffer());
      if (url.searchParams.get('uploadType') === 'resumable') return this.#startSession(body);
      const [metadata, bytes] = parseMultipart(request.headers.get('Content-Type') ?? '', body);
      return this.#create(metadata, bytes);
    }
    if (request.method === 'PUT' && path.startsWith('/upload/session/')) {
      const session = this.#sessions.get(path.slice(16));
      if (session === undefined) return new Response('no session', { status: 404 });
      return this.#create(session, new Uint8Array(await request.arrayBuffer()));
    }
    if (request.method === 'PATCH' && path.startsWith('/upload/drive/v3/files/')) {
      const file = this.#files.get(path.slice(23));
      if (file === undefined) return new Response('not found', { status: 404 });
      file.bytes = new Uint8Array(await request.arrayBuffer());
      return Response.json({ id: file.id, name: file.name });
    }
    return new Response(`unhandled ${request.method} ${url.href}`, { status: 404 });
  };

  #list(url: URL): Response {
    const query = url.searchParams.get('q') ?? '';
    const matches = [...this.#files.values()].filter((file) => matchesQuery(file, query));
    const pageSize = Math.min(Number(url.searchParams.get('pageSize') ?? '100'), this.#maxPageSize);
    const offset = Number(url.searchParams.get('pageToken') ?? '0');
    const page = matches.slice(offset, offset + pageSize);
    const next = offset + page.length;
    return Response.json({
      files: page.map(({ id, name }) => ({ id, name })),
      ...(next < matches.length ? { nextPageToken: String(next) } : {}),
    });
  }

  #download(id: string): Response {
    const file = this.#files.get(decodeURIComponent(id));
    return file === undefined ? new Response('not found', { status: 404 }) : new Response(new Uint8Array(file.bytes));
  }

  #create(metadata: unknown, bytes: Uint8Array): Response {
    const id = `file-${this.#nextId++}`;
    const { name, mimeType, parents } = metadataOf(metadata);
    this.#files.set(id, { id, name, mimeType: mimeType ?? 'application/octet-stream', parents, bytes });
    return Response.json({ id, name });
  }

  #startSession(body: Uint8Array): Response {
    const { name, parents } = metadataOf(JSON.parse(new TextDecoder().decode(body)));
    const session = `session-${this.#nextId++}`;
    this.#sessions.set(session, { name, parents });
    return new Response(null, { headers: { Location: `https://www.googleapis.com/upload/session/${session}` } });
  }
}

function metadataOf(json: unknown): { name: string; mimeType?: string; parents: string[] } {
  if (typeof json !== 'object' || json === null) throw new TypeError('Metadata is no object');
  const name: unknown = Reflect.get(json, 'name');
  const mimeType: unknown = Reflect.get(json, 'mimeType');
  const parents: unknown = Reflect.get(json, 'parents');
  if (typeof name !== 'string') throw new TypeError('Metadata without name');
  return {
    name,
    ...(typeof mimeType === 'string' ? { mimeType } : {}),
    parents: Array.isArray(parents) ? parents.filter((parent) => typeof parent === 'string') : [],
  };
}

/** Queries are conjunctions of clauses - each expected fragment is checked rather than parsed. */
function matchesQuery(file: FakeDriveFile, query: string): boolean {
  const isFolder = file.mimeType === folderMimeType;
  if (query.includes(`mimeType='${folderMimeType}'`) && !isFolder) return false;
  if (query.includes(`mimeType!='${folderMimeType}'`) && isFolder) return false;
  const name = /name='([^']*)'/.exec(query)?.[1];
  if (name !== undefined && file.name !== name) return false;
  const parent = /'([^']*)' in parents/.exec(query)?.[1];
  return parent === undefined || file.parents.includes(parent);
}

/** Splits a `multipart/related` body into its JSON metadata and its media bytes. */
function parseMultipart(contentType: string, body: Uint8Array): [unknown, Uint8Array] {
  const boundary = /boundary=([^;]+)/.exec(contentType)?.[1];
  if (boundary === undefined) throw new TypeError('No multipart boundary');
  // One char per byte, so slicing the string slices the bytes alike.
  const text = Array.from(body, (byte) => String.fromCharCode(byte)).join('');
  const parts = text
    .split(`--${boundary}`)
    .slice(1, -1)
    .map((part) => part.slice(part.indexOf('\r\n\r\n') + 4, part.length - 2));
  const [metadata = '', media = ''] = parts;
  return [JSON.parse(metadata), Uint8Array.from(media, (char) => char.charCodeAt(0))];
}
