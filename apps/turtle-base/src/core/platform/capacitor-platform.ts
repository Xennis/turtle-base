import { SecureStorage } from '@aparajita/capacitor-secure-storage';
import { FileOpener } from '@capacitor-community/file-opener';
import { AppLauncher } from '@capacitor/app-launcher';
import { Capacitor, registerPlugin, SystemBars, SystemBarsStyle } from '@capacitor/core';
import { Directory, Filesystem } from '@capacitor/filesystem';
import { Preferences } from '@capacitor/preferences';
import { FilePicker } from '@capawesome/capacitor-file-picker';
import type {
  FileDirectory,
  KeyValueStore,
  PickFilesOptions,
  Platform,
  SecretStorage,
  SqlDriver,
  SqlValue,
} from '@turtle-base/platform';
import mime from 'mime';

/** The Android shell's own plugins - see apps/mobile/android (SqlPlugin.java, HttpPlugin.java). */
interface TurtleSqlPlugin {
  open(options: { name: string }): Promise<void>;
  execute(options: { sql: string; params: (null | number | string)[] }): Promise<{
    rows: Record<string, null | number | string>[];
    changes: number;
    lastInsertRowid: number;
  }>;
  close(): Promise<void>;
}

interface TurtleHttpPlugin {
  request(options: {
    url: string;
    method: string;
    headers: [string, string][];
    body: string | null;
  }): Promise<{ status: number; statusText: string; headers: [string, string][]; body: string }>;
}

const TurtleSql = registerPlugin<TurtleSqlPlugin>('TurtleSql');
const TurtleHttp = registerPlugin<TurtleHttpPlugin>('TurtleHttp');

const filesFolder = 'files';
const tempFolder = `${filesFolder}/tmp`;

/** Below this, chunks of a stream being written are collected before they cross the bridge. */
const writeBatchBytes = 1024 * 1024;

/**
 * The {@link Platform} of the Android shell: Capacitor plugins, plus the
 * shell's own for SQL and HTTP. Files are served to the web view by
 * Capacitor's local server, so reading them needs no base64 on the way back.
 */
export async function createCapacitorPlatform(): Promise<Platform> {
  await TurtleSql.open({ name: 'turtle-base.sqlite' });
  // Checked first - Capacitor logs a failed mkdir as an error even when it's caught.
  if (!(await fileExists('tmp')))
    await Filesystem.mkdir({ path: tempFolder, directory: Directory.Data, recursive: true });
  const { uri: filesUri } = await Filesystem.getUri({ path: filesFolder, directory: Directory.Data });
  return {
    kind: 'android',
    sql: sql,
    prefs: await loadPrefs(),
    secrets,
    files: filesIn(filesUri),
    fetch: nativeFetch,
    openExternal: async (url) => {
      await AppLauncher.openUrl({ url });
    },
    pickFiles,
    openFile,
    // The style names the bars' background: light icons on a dark page.
    setSystemBarsDark: (dark) => SystemBars.setStyle({ style: dark ? SystemBarsStyle.Dark : SystemBarsStyle.Light }),
    googleAuth: undefined,
  };
}

const sql: SqlDriver = {
  execute: async (statement, params) => {
    const result = await TurtleSql.execute({ sql: statement, params: params.map(bridgeable) });
    return { rows: result.rows, changes: result.changes, lastInsertRowid: result.lastInsertRowid };
  },
  close: () => TurtleSql.close(),
};

/** Only JSON crosses the bridge. */
function bridgeable(value: SqlValue): null | number | string {
  if (typeof value === 'bigint') {
    if (value > BigInt(Number.MAX_SAFE_INTEGER) || value < BigInt(Number.MIN_SAFE_INTEGER)) {
      throw new RangeError(`${value} doesn't fit through the bridge`);
    }
    return Number(value);
  }
  if (value instanceof Uint8Array) throw new TypeError('Blobs are not supported on Android');
  return value;
}

/** All prefs read at start - the interface reads synchronously. */
async function loadPrefs(): Promise<KeyValueStore> {
  const { keys } = await Preferences.keys();
  const values = new Map<string, string>();
  for (const key of keys) {
    const { value } = await Preferences.get({ key });
    if (value !== null) values.set(key, value);
  }
  return {
    get: (key) => values.get(key),
    set: async (key, value) => {
      values.set(key, value);
      await Preferences.set({ key, value });
    },
    remove: async (key) => {
      values.delete(key);
      await Preferences.remove({ key });
    },
  };
}

/** In the Android Keystore. */
const secrets: SecretStorage = {
  get: async (key) => (await SecureStorage.getItem(key)) ?? undefined,
  set: (key, value) => SecureStorage.setItem(key, value),
  remove: (key) => SecureStorage.removeItem(key),
};

function pathOf(name: string): string {
  return `${filesFolder}/${name}`;
}

function fileExists(name: string): Promise<boolean> {
  return Filesystem.stat({ path: pathOf(name), directory: Directory.Data }).then(
    () => true,
    () => false,
  );
}

function filesIn(filesUri: string): FileDirectory {
  const urlOf = (name: string) => Capacitor.convertFileSrc(`${filesUri}/${encodeURIComponent(name)}`);

  async function bodyOf(name: string): Promise<ReadableStream<Uint8Array>> {
    const response = await fetch(urlOf(name));
    if (!response.ok || response.body === null) throw new Error(`No file ${name} (${response.status})`);
    return response.body;
  }

  return {
    list: async () =>
      (await Filesystem.readdir({ path: filesFolder, directory: Directory.Data })).files
        .filter((entry) => entry.type === 'file')
        .map((entry) => entry.name),
    exists: fileExists,
    size: async (name) => (await Filesystem.stat({ path: pathOf(name), directory: Directory.Data })).size,
    read: bodyOf,
    readHead: async (name, length) => {
      const reader = (await bodyOf(name)).getReader();
      const head = new Uint8Array(length);
      let filled = 0;
      while (filled < length) {
        const { done, value } = await reader.read();
        if (done) break;
        const part = value.subarray(0, length - filled);
        head.set(part, filled);
        filled += part.length;
      }
      await reader.cancel();
      return head.slice(0, filled);
    },
    writeTemp: async (bytes) => {
      const handle = crypto.randomUUID();
      const path = `${tempFolder}/${handle}`;
      await Filesystem.writeFile({ path, directory: Directory.Data, data: '' });
      let pending: Uint8Array[] = [];
      let pendingBytes = 0;
      const flush = async () => {
        if (pendingBytes === 0) return;
        await Filesystem.appendFile({ path, directory: Directory.Data, data: toBase64(concat(pending, pendingBytes)) });
        pending = [];
        pendingBytes = 0;
      };
      for await (const chunk of bytes) {
        pending.push(chunk);
        pendingBytes += chunk.length;
        if (pendingBytes >= writeBatchBytes) await flush();
      }
      await flush();
      return handle;
    },
    commitTemp: async (handle, name) => {
      // A rename doesn't replace an existing file here, e.g. a thumbnail made again.
      if (await fileExists(name)) await Filesystem.deleteFile({ path: pathOf(name), directory: Directory.Data });
      await Filesystem.rename({
        from: `${tempFolder}/${handle}`,
        to: pathOf(name),
        directory: Directory.Data,
        toDirectory: Directory.Data,
      });
    },
    discardTemp: (handle) => Filesystem.deleteFile({ path: `${tempFolder}/${handle}`, directory: Directory.Data }),
    urlOf,
  };
}

/** Runs in the shell (TurtleHttp), so CORS doesn't apply. Whole bodies, as base64 over the bridge. */
const nativeFetch: typeof fetch = async (input, init) => {
  const request = new Request(input, init);
  const body = request.body === null ? null : toBase64(new Uint8Array(await request.arrayBuffer()));
  const response = await TurtleHttp.request({
    url: request.url,
    method: request.method,
    headers: [...request.headers.entries()],
    body,
  });
  const nullBody = [101, 204, 205, 304].includes(response.status);
  return new Response(nullBody ? null : fromBase64(response.body), {
    status: response.status,
    statusText: response.statusText,
    headers: response.headers,
  });
};

async function pickFiles(options: PickFilesOptions) {
  const types =
    options.imagesOnly === true
      ? ['image/*']
      : options.extensions?.flatMap((extension) => mime.getType(extension) ?? []);
  try {
    const { files } = await FilePicker.pickFiles({
      ...(types === undefined || types.length === 0 ? {} : { types }),
      limit: options.multiple ? 0 : 1,
      readData: false,
    });
    return await Promise.all(
      files.map(async (file) => {
        if (file.path === undefined) throw new Error(`No path for ${file.name}`);
        const response = await fetch(Capacitor.convertFileSrc(file.path));
        if (response.body === null) throw new Error(`Can't read ${file.name}`);
        return { name: file.name, bytes: response.body };
      }),
    );
  } catch (error) {
    if (error instanceof Error && error.message === 'pickFiles canceled.') return [];
    throw error;
  }
}

/** Opens a copy under the attachment's own name, so the app chosen sees its type. */
async function openFile(name: string, displayName: string): Promise<void> {
  const folder = `open/${crypto.randomUUID()}`;
  await Filesystem.mkdir({ path: folder, directory: Directory.Cache, recursive: true });
  // The name came from another device through sync - no path in it.
  const path = `${folder}/${displayName.replaceAll('/', '_')}`;
  await Filesystem.copy({
    from: `${filesFolder}/${name}`,
    directory: Directory.Data,
    to: path,
    toDirectory: Directory.Cache,
  });
  const { uri } = await Filesystem.getUri({ path, directory: Directory.Cache });
  const contentType = mime.getType(displayName);
  await FileOpener.open({ filePath: uri, ...(contentType === null ? {} : { contentType }) });
}

function concat(chunks: readonly Uint8Array[], length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return bytes;
}

function toBase64(bytes: Uint8Array): string {
  let binary = '';
  // In slices - String.fromCharCode takes its arguments on the stack.
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function fromBase64(base64: string): Uint8Array<ArrayBuffer> {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
