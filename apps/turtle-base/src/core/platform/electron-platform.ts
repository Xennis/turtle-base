import {
  desktopFileScheme,
  type DesktopBridge,
  type FileDirectory,
  type GoogleAuthenticator,
  type KeyValueStore,
  type Platform,
  type SecretStorage,
  type SqlDriver,
} from '@turtle-base/platform';

declare global {
  interface Window {
    /** Set by the desktop shell's preload - see apps/desktop. */
    readonly turtleDesktop?: DesktopBridge;
  }
}

/**
 * The {@link Platform} of the desktop shell: every call goes through the
 * preload's bridge into Electron's main process (see `IpcContract`).
 */
export async function createElectronPlatform(bridge: DesktopBridge): Promise<Platform> {
  const prefs = new Map(Object.entries(await bridge.invoke('prefs:load')));
  return {
    kind: 'desktop',
    sql: sqlOf(bridge),
    prefs: prefsOf(bridge, prefs),
    secrets: secretsOf(bridge),
    files: filesOf(bridge),
    fetch: fetchOf(bridge),
    openExternal: (url) => bridge.invoke('shell:openExternal', url),
    pickFiles: async ({ multiple, extensions }) =>
      (await bridge.invoke('files:pick', { multiple, extensions })).map(({ name, bytes }) => ({
        name,
        bytes: new Blob([new Uint8Array(bytes)]).stream(),
      })),
    openFile: (name, displayName) => bridge.invoke('files:open', name, displayName),
    googleAuth: (await bridge.invoke('googleAuth:available')) ? googleAuthOf(bridge) : undefined,
  };
}

/** The sign-in runs in the main process - it needs a local server for the redirect and keeps the token there. */
function googleAuthOf(bridge: DesktopBridge): GoogleAuthenticator {
  return {
    signInSilently: () => bridge.invoke('googleAuth:signInSilently'),
    signIn: () => bridge.invoke('googleAuth:signIn'),
    signOut: () => bridge.invoke('googleAuth:signOut'),
    accessToken: () => bridge.invoke('googleAuth:accessToken'),
  };
}

function sqlOf(bridge: DesktopBridge): SqlDriver {
  return {
    execute: (sql, params) => bridge.invoke('sql:execute', sql, params),
    // The connection belongs to the main process and lives as long as it does.
    close: () => Promise.resolve(),
  };
}

/** Kept in memory as well, so reads stay synchronous like the interface wants. */
function prefsOf(bridge: DesktopBridge, values: Map<string, string>): KeyValueStore {
  return {
    get: (key) => values.get(key),
    set: (key, value) => {
      values.set(key, value);
      return bridge.invoke('prefs:set', key, value);
    },
    remove: (key) => {
      values.delete(key);
      return bridge.invoke('prefs:remove', key);
    },
  };
}

function secretsOf(bridge: DesktopBridge): SecretStorage {
  return {
    get: (key) => bridge.invoke('secrets:get', key),
    set: (key, value) => bridge.invoke('secrets:set', key, value),
    remove: (key) => bridge.invoke('secrets:remove', key),
  };
}

/** Whole files cross the IPC boundary at once - streams can't. */
function filesOf(bridge: DesktopBridge): FileDirectory {
  return {
    list: () => bridge.invoke('files:list'),
    exists: (name) => bridge.invoke('files:exists', name),
    size: (name) => bridge.invoke('files:size', name),
    read: async (name) => new Blob([new Uint8Array(await bridge.invoke('files:read', name))]).stream(),
    readHead: (name, length) => bridge.invoke('files:readHead', name, length),
    writeTemp: async (bytes) =>
      bridge.invoke('files:writeTemp', new Uint8Array(await new Response(bytes).arrayBuffer())),
    commitTemp: (handle, name) => bridge.invoke('files:commitTemp', handle, name),
    discardTemp: (handle) => bridge.invoke('files:discardTemp', handle),
    urlOf: (name) => `${desktopFileScheme}://files/${encodeURIComponent(name)}`,
  };
}

/** A `fetch` that runs in the main process, so CORS doesn't apply. */
function fetchOf(bridge: DesktopBridge): typeof fetch {
  return async (input, init) => {
    const request = new Request(input, init);
    const body = request.body === null ? null : new Uint8Array(await request.arrayBuffer());
    const response = await bridge.invoke('fetch', {
      url: request.url,
      method: request.method,
      headers: [...request.headers.entries()],
      body,
    });
    const nullBody = [101, 204, 205, 304].includes(response.status);
    return new Response(nullBody ? null : new Uint8Array(response.body), {
      status: response.status,
      statusText: response.statusText,
      headers: response.headers.map(([name, value]): [string, string] => [name, value]),
    });
  };
}
