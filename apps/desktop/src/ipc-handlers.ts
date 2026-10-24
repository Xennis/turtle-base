import type { IpcChannel, IpcContract, SqlDriver } from '@turtle-base/platform';
import { mkdtemp, copyFile, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, join } from 'node:path';

import { BrowserWindow, dialog, ipcMain, net, shell, type IpcMainInvokeEvent } from 'electron';

import type { DiskFileDirectory } from './file-directory.ts';
import type { PrefsFile } from './prefs-file.ts';
import type { SecretsFile } from './secrets-file.ts';

type Handler<C extends IpcChannel> = (
  ...args: Parameters<IpcContract[C]>
) => ReturnType<IpcContract[C]> | Promise<ReturnType<IpcContract[C]>>;

/**
 * Handles every channel of IpcContract. Calls are only taken from frames of
 * the app itself (`isTrusted`), never from a page that got into the window
 * some other way.
 */
export function registerIpcHandlers(options: {
  sql: SqlDriver;
  prefs: PrefsFile;
  secrets: SecretsFile;
  files: DiskFileDirectory;
  isTrusted: (url: string) => boolean;
}): void {
  const { sql, prefs, secrets, files, isTrusted } = options;

  function handle<C extends IpcChannel>(channel: C, handler: Handler<C>): void {
    ipcMain.handle(channel, (event: IpcMainInvokeEvent, ...args: unknown[]) => {
      const url = event.senderFrame?.url ?? '';
      if (!isTrusted(url)) throw new Error(`Untrusted IPC sender: ${url}`);
      // The preload only forwards the typed calls of the app's own renderer, checked above.
      // oxlint-disable-next-line typescript/no-unsafe-type-assertion
      return handler(...(args as Parameters<IpcContract[C]>));
    });
  }

  handle('sql:execute', (statement, params) => sql.execute(statement, params));

  handle('prefs:load', () => prefs.all());
  handle('prefs:set', (key, value) => prefs.set(key, value));
  handle('prefs:remove', (key) => prefs.remove(key));

  handle('secrets:get', (key) => secrets.get(key));
  handle('secrets:set', (key, value) => secrets.set(key, value));
  handle('secrets:remove', (key) => secrets.remove(key));

  handle('files:list', () => files.list());
  handle('files:exists', (name) => files.exists(name));
  handle('files:size', (name) => files.size(name));
  handle('files:read', (name) => files.read(name));
  handle('files:readHead', (name, length) => files.readHead(name, length));
  handle('files:writeTemp', (bytes) => files.writeTemp(bytes));
  handle('files:commitTemp', (handle_, name) => files.commitTemp(handle_, name));
  handle('files:discardTemp', (handle_) => files.discardTemp(handle_));

  handle('files:pick', async ({ multiple, extensions }) => {
    const window = BrowserWindow.getFocusedWindow();
    const dialogOptions: Electron.OpenDialogOptions = {
      properties: multiple ? ['openFile', 'multiSelections'] : ['openFile'],
      ...(extensions === undefined ? {} : { filters: [{ name: 'Files', extensions: [...extensions] }] }),
    };
    const { canceled, filePaths } = await (window === null
      ? dialog.showOpenDialog(dialogOptions)
      : dialog.showOpenDialog(window, dialogOptions));
    if (canceled) return [];
    return Promise.all(filePaths.map(async (path) => ({ name: basename(path), bytes: await readFile(path) })));
  });

  // A copy under its real name in a fresh temporary folder - the store names files by hash, without extension,
  // and the system picks the app by the name.
  handle('files:open', async (name, displayName) => {
    const copy = join(await mkdtemp(join(tmpdir(), 'turtle-base-open-')), basename(displayName));
    await copyFile(files.fileOf(name), copy);
    const error = await shell.openPath(copy);
    if (error.length > 0) throw new Error(error);
  });

  handle('fetch', async (request) => {
    const response = await net.fetch(request.url, {
      method: request.method,
      headers: request.headers.map(([name, value]): [string, string] => [name, value]),
      ...(request.body === null ? {} : { body: new Uint8Array(request.body) }),
    });
    return {
      status: response.status,
      statusText: response.statusText,
      headers: [...response.headers.entries()],
      body: new Uint8Array(await response.arrayBuffer()),
    };
  });

  handle('shell:openExternal', async (url) => {
    const { protocol } = new URL(url);
    if (!['https:', 'http:', 'mailto:', 'tel:'].includes(protocol)) throw new Error(`Refusing to open ${url}`);
    await shell.openExternal(url);
  });
}
