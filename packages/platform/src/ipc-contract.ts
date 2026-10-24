import type { SqlResult, SqlValue } from './sql-driver.ts';

/** A request as it crosses the IPC boundary - `Request` itself can't be cloned. */
export interface IpcRequest {
  readonly url: string;
  readonly method: string;
  readonly headers: readonly (readonly [string, string])[];
  readonly body: Uint8Array | null;
}

export interface IpcResponse {
  readonly status: number;
  readonly statusText: string;
  readonly headers: readonly (readonly [string, string])[];
  readonly body: Uint8Array;
}

/**
 * Every call the desktop renderer makes into Electron's main process, by
 * channel: its arguments and result. The main process handles exactly these,
 * the preload exposes exactly these, and the renderer's client is typed by
 * them - one source for both sides.
 */
export interface IpcContract {
  'sql:execute': (sql: string, params: readonly SqlValue[]) => SqlResult;

  /** All prefs at once - the renderer keeps them in memory, so reads stay synchronous. */
  'prefs:load': () => Record<string, string>;
  'prefs:set': (key: string, value: string) => void;
  'prefs:remove': (key: string) => void;

  'secrets:get': (key: string) => string | undefined;
  'secrets:set': (key: string, value: string) => void;
  'secrets:remove': (key: string) => void;

  'files:list': () => string[];
  'files:exists': (name: string) => boolean;
  'files:size': (name: string) => number;
  'files:read': (name: string) => Uint8Array;
  'files:readHead': (name: string, length: number) => Uint8Array;
  'files:writeTemp': (bytes: Uint8Array) => string;
  'files:commitTemp': (handle: string, name: string) => void;
  'files:discardTemp': (handle: string) => void;

  fetch: (request: IpcRequest) => IpcResponse;
  'shell:openExternal': (url: string) => void;
}

export type IpcChannel = keyof IpcContract;

/** The channels, for the preload's allowlist. `satisfies` keeps it complete. */
export const ipcChannels = Object.keys({
  'sql:execute': true,
  'prefs:load': true,
  'prefs:set': true,
  'prefs:remove': true,
  'secrets:get': true,
  'secrets:set': true,
  'secrets:remove': true,
  'files:list': true,
  'files:exists': true,
  'files:size': true,
  'files:read': true,
  'files:readHead': true,
  'files:writeTemp': true,
  'files:commitTemp': true,
  'files:discardTemp': true,
  fetch: true,
  'shell:openExternal': true,
} satisfies Record<IpcChannel, true>);

/** What the preload exposes to the renderer as `window.turtleDesktop`. */
export interface DesktopBridge {
  invoke<C extends IpcChannel>(channel: C, ...args: Parameters<IpcContract[C]>): Promise<ReturnType<IpcContract[C]>>;
}

/** The scheme the main process serves attachment files under, e.g. `turtle-file://files/sha256-…`. */
export const desktopFileScheme = 'turtle-file';
