import { mkdirSync } from 'node:fs';
import { join, normalize, resolve, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

import { LoopbackGoogleAuthenticator } from '@turtle-base/crdt-file-sync-google-drive';
import { listenForRedirectOnNode } from '@turtle-base/crdt-file-sync-google-drive/desktop';
import { contentSecurityPolicy, desktopFileScheme } from '@turtle-base/platform';
import { createNodeSqlDriver } from '@turtle-base/platform/node';
import { app, BrowserWindow, net, protocol, shell } from 'electron';

import { DiskFileDirectory } from './file-directory.ts';
import { registerIpcHandlers } from './ipc-handlers.ts';
import { PrefsFile } from './prefs-file.ts';
import { SecretsFile } from './secrets-file.ts';
import { titleBarOptions } from './title-bar.ts';

/** The renderer is served from here, not from file:// - a real origin, and nothing else of the disk reachable. */
const appOrigin = 'app://turtle';

/** Set by `mise run dev-desktop`: load the renderer from Vite's dev server instead, with hot reload. */
const devServerUrl = process.env['TURTLE_DEV_SERVER_URL'];

/** The built renderer: in the packaged app among its resources (see electron-builder.yml), else `apps/turtle-base/dist`. */
const rendererDir = resolve(
  process.env['TURTLE_RENDERER_DIR'] ??
    (app.isPackaged ? join(process.resourcesPath, 'renderer') : join(import.meta.dirname, '../../turtle-base/dist')),
);
protocol.registerSchemesAsPrivileged([
  { scheme: 'app', privileges: { standard: true, secure: true, supportFetchAPI: true } },
  { scheme: desktopFileScheme, privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true } },
]);

function isTrusted(url: string): boolean {
  if (url.startsWith(`${appOrigin}/`)) return true;
  return devServerUrl !== undefined && url.startsWith(devServerUrl);
}

function serveRenderer(): void {
  protocol.handle('app', async (request) => {
    const url = new URL(request.url);
    if (url.host !== 'turtle') return new Response('Not found', { status: 404 });
    const path = normalize(join(rendererDir, decodeURIComponent(url.pathname)));
    if (!path.startsWith(rendererDir + sep)) return new Response('Not found', { status: 404 });
    const response = await net.fetch(pathToFileURL(path).href);
    const headers = new Headers(response.headers);
    if (path.endsWith('.html')) headers.set('Content-Security-Policy', contentSecurityPolicy);
    return new Response(response.body, { status: response.status, headers });
  });
}

function serveFiles(files: DiskFileDirectory): void {
  protocol.handle(desktopFileScheme, async (request) => {
    const name = decodeURIComponent(new URL(request.url).pathname.slice(1));
    // A missing file (e.g. a thumbnail not synced yet) is a 404 the page handles, not an error.
    if (!(await files.exists(name).catch(() => false))) return new Response('Not found', { status: 404 });
    return net.fetch(pathToFileURL(files.fileOf(name)).href);
  });
}

function createWindow(): void {
  const window = new BrowserWindow({
    width: 1200,
    height: 800,
    title: 'turtle-base',
    // Linux shows it in the dock and window switcher; macOS takes the bundle's.
    icon: join(import.meta.dirname, '../resources/icon.png'),
    ...titleBarOptions,
    webPreferences: {
      preload: join(import.meta.dirname, 'preload.cjs'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
    },
  });
  // Links leave the app for the system browser; the window itself only ever shows the app.
  window.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('https://') || url.startsWith('http://')) void shell.openExternal(url);
    return { action: 'deny' };
  });
  window.webContents.on('will-navigate', (event, url) => {
    if (!isTrusted(url)) event.preventDefault();
  });
  void window.loadURL(devServerUrl ?? `${appOrigin}/index.html`);
}

/** A variable of the environment the app runs in - else the one it was built with (see vite.config.ts). */
function fromEnvironment(name: string, bundled: string): string {
  const value = process.env[name];
  return value !== undefined && value.length > 0 ? value : bundled;
}

/** The Drive sync's sign-in, when an OAuth client is configured - see packages/crdt-file-sync-google-drive. */
function createGoogleAuth(secrets: SecretsFile): LoopbackGoogleAuthenticator | undefined {
  const clientId = fromEnvironment('DRIVE_DESKTOP_CLIENT_ID', bundledDriveClientId);
  const clientSecret = fromEnvironment('DRIVE_DESKTOP_CLIENT_SECRET', bundledDriveClientSecret);
  if (clientId.length === 0 || clientSecret.length === 0) return undefined;
  return new LoopbackGoogleAuthenticator({
    clientId,
    clientSecret,
    secrets: {
      get: (key) => Promise.resolve(secrets.get(key)),
      set: (key, value) => Promise.resolve(secrets.set(key, value)),
      remove: (key) => Promise.resolve(secrets.remove(key)),
    },
    // net.fetch looked up per call, so a stub of it (see e2e/smoke.e2e.ts) answers this too.
    fetch: (input, init) => net.fetch(input instanceof URL ? input.href : input, init),
    openBrowser: (url) => shell.openExternal(url),
    listenForRedirect: listenForRedirectOnNode,
  });
}

// Not a top-level await: Electron holds back `ready` until the main module has finished evaluating.
void app.whenReady().then(() => {
  const userData = app.getPath('userData');
  mkdirSync(userData, { recursive: true });
  const files = new DiskFileDirectory(join(userData, 'files'));
  const secrets = new SecretsFile(join(userData, 'secrets.json'));
  registerIpcHandlers({
    sql: createNodeSqlDriver(join(userData, 'turtle-base.sqlite')),
    prefs: new PrefsFile(join(userData, 'prefs.json')),
    secrets,
    files,
    googleAuth: createGoogleAuth(secrets),
    isTrusted,
  });
  serveRenderer();
  serveFiles(files);
  createWindow();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});
