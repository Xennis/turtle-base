import { invoke } from '@tauri-apps/api/core';
import { appCacheDir, appDataDir } from '@tauri-apps/api/path';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { open } from '@tauri-apps/plugin-dialog';
import { copyFile, mkdir, readFile } from '@tauri-apps/plugin-fs';
import { fetch as shellFetch } from '@tauri-apps/plugin-http';
import { openPath, openUrl } from '@tauri-apps/plugin-opener';
import { platform } from '@tauri-apps/plugin-os';
import { load } from '@tauri-apps/plugin-store';
import type {
  KeyValueStore,
  PickedFile,
  PickFilesOptions,
  Platform,
  SecretStorage,
  SqlDriver,
  SqlRow,
  SqlValue,
} from '@turtle-base/platform';

import { filesIn } from './tauri-files.ts';
import { desktopGoogleAuth } from './tauri-google-auth.ts';

/**
 * The {@link Platform} of the Tauri shell (apps/shell) on the desktop and on
 * Android: Tauri's plugins, plus the shell's own commands for SQL and
 * secrets.
 */
export async function createTauriPlatform(): Promise<Platform> {
  const data = await appDataDir();
  const cache = await appCacheDir();
  const os = platform();
  return {
    kind: os === 'android' ? 'android' : 'desktop',
    // macOS lays the window's buttons over the page (see tauri.macos.conf.json), Linux draws its own title bar.
    pageTitleBar: os === 'macos',
    sql,
    prefs: await loadPrefs(),
    secrets,
    files: filesIn(`${data}/files`),
    // Runs in the shell, so CORS doesn't apply.
    fetch: shellFetch,
    openExternal: (url) => openUrl(url),
    pickFiles,
    openFile: (name, displayName) => openFile(`${data}/files/${name}`, `${cache}/open`, displayName),
    findFlutterAppData: () => Promise.resolve(undefined),
    // The title bar (Linux) and the window's buttons (macOS) follow the window's theme.
    matchWindowChrome: ({ dark }) => getCurrentWindow().setTheme(dark ? 'dark' : 'light'),
    googleAuth: os === 'android' ? undefined : desktopGoogleAuth(secrets),
  };
}

/** A value as it crosses into the shell - JSON, a blob as its bytes. */
type ShellValue = null | number | string | number[];

interface ShellResult {
  readonly rows: readonly Readonly<Record<string, ShellValue>>[];
  readonly changes: number;
  readonly lastInsertRowid: number;
}

const sql: SqlDriver = {
  execute: async (statement, params) => {
    const result = await invoke<ShellResult>('sql_execute', { sql: statement, params: params.map(toShell) });
    return { rows: result.rows.map(rowOf), changes: result.changes, lastInsertRowid: result.lastInsertRowid };
  },
  // The connection belongs to the shell and lives as long as it does.
  close: () => Promise.resolve(),
};

function toShell(value: SqlValue): ShellValue {
  if (typeof value === 'bigint') {
    if (value > BigInt(Number.MAX_SAFE_INTEGER) || value < BigInt(Number.MIN_SAFE_INTEGER)) {
      throw new RangeError(`${value} doesn't fit into JSON`);
    }
    return Number(value);
  }
  return value instanceof Uint8Array ? Array.from(value) : value;
}

function rowOf(row: Readonly<Record<string, ShellValue>>): SqlRow {
  return Object.fromEntries(
    Object.entries(row).map(([name, value]) => [name, Array.isArray(value) ? new Uint8Array(value) : value]),
  );
}

/** All prefs read at start - the interface reads synchronously. */
async function loadPrefs(): Promise<KeyValueStore> {
  const store = await load('prefs.json', { autoSave: false });
  const values = new Map(await store.entries<string>());
  return {
    get: (key) => values.get(key),
    set: async (key, value) => {
      values.set(key, value);
      await store.set(key, value);
      await store.save();
    },
    remove: async (key) => {
      values.delete(key);
      await store.delete(key);
      await store.save();
    },
  };
}

/** In the OS keyring, see the shell's secrets.rs. */
const secrets: SecretStorage = {
  get: async (key) => (await invoke<string | null>('secrets_get', { key })) ?? undefined,
  set: (key, value) => invoke('secrets_set', { key, value }),
  remove: (key) => invoke('secrets_remove', { key }),
};

async function pickFiles({ multiple, extensions, imagesOnly }: PickFilesOptions): Promise<PickedFile[]> {
  const picked: string | string[] | null = await open({
    multiple,
    ...(extensions === undefined ? {} : { filters: [{ name: 'Files', extensions: [...extensions] }] }),
    ...(imagesOnly === true ? { pickerMode: 'image' as const } : {}),
  });
  const paths = picked === null ? [] : typeof picked === 'string' ? [picked] : picked;
  return Promise.all(
    paths.map(async (path) => ({ name: nameOf(path), bytes: new Blob([await readFile(path)]).stream() })),
  );
}

function nameOf(path: string): string {
  return decodeURIComponent(path.slice(path.lastIndexOf('/') + 1));
}

/**
 * Opens a copy under the attachment's own name in a fresh folder of `folder` -
 * the store names files by hash, without extension, and the system picks the
 * app by the name.
 */
async function openFile(path: string, folder: string, displayName: string): Promise<void> {
  const copyFolder = `${folder}/${crypto.randomUUID()}`;
  await mkdir(copyFolder, { recursive: true });
  // The name came from another device through sync - no path in it.
  const copy = `${copyFolder}/${displayName.replaceAll('/', '_')}`;
  await copyFile(path, copy);
  await openPath(copy);
}
