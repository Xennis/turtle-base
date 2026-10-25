import { load } from '@tauri-apps/plugin-store';
import type { SecretStorage } from '@turtle-base/platform';

import type { ShellIo } from './tauri-platform.ts';

/**
 * What the smoke test sets on `window` (through WebDriver or Playwright) to
 * stand in for the world outside the app. Each hook is asked first; without
 * one, or when it passes, the shell does the real thing.
 */
export interface E2eHooks {
  /** An answer to a request instead of the network - undefined lets it through. */
  answer?(request: { url: string; headers: Record<string, string> }): E2eAnswer | undefined;
  /** What the file dialog picks, base64. */
  pickFiles?: readonly { name: string; base64: string }[];
  /** Opens `url` instead of the system - false lets it through. */
  openExternal?(url: string): Promise<boolean>;
}

export interface E2eAnswer {
  readonly status?: number;
  readonly headers?: Record<string, string>;
  /** As base64 - a JSON or text body too. */
  readonly base64?: string;
}

declare global {
  interface Window {
    turtleE2e?: E2eHooks;
  }
}

/** The shell's I/O with the test's hooks in front - and secrets in a file, since a test machine has no keyring. */
export function withE2eHooks(io: ShellIo): ShellIo {
  return {
    secrets: fileSecrets(),
    fetch: async (input, init) => {
      const request = new Request(input, init);
      const answer = window.turtleE2e?.answer?.({ url: request.url, headers: Object.fromEntries(request.headers) });
      if (answer === undefined) return io.fetch(request);
      const body = answer.base64 === undefined ? null : bytesOf(answer.base64);
      return new Response(body, { status: answer.status ?? 200, headers: answer.headers ?? {} });
    },
    openExternal: async (url) => {
      if (!((await window.turtleE2e?.openExternal?.(url)) ?? false)) await io.openExternal(url);
    },
    pickFiles: async (options) => {
      const picked = window.turtleE2e?.pickFiles;
      if (picked === undefined) return io.pickFiles(options);
      return picked.map(({ name, base64 }) => ({ name, bytes: new Blob([bytesOf(base64)]).stream() }));
    },
  };
}

function fileSecrets(): SecretStorage {
  const store = load('e2e-secrets.json', { autoSave: false });
  return {
    get: async (key) => (await store).get<string>(key),
    set: async (key, value) => {
      await (await store).set(key, value);
      await (await store).save();
    },
    remove: async (key) => {
      await (await store).delete(key);
      await (await store).save();
    },
  };
}

function bytesOf(base64: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
}
