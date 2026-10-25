import { Channel, invoke } from '@tauri-apps/api/core';
import { type ListenForRedirect, LoopbackGoogleAuthenticator } from '@turtle-base/crdt-file-sync-google-drive';
import type { GoogleAuthenticator } from '@turtle-base/platform';

import type { ShellIo } from './tauri-platform.ts';

/**
 * Google sign-in on the desktop: the loopback flow in the user's browser,
 * with the "Desktop app" OAuth client the build was given (see vite.config.ts).
 * Undefined without one - the app then hides Drive sync.
 */
export function desktopGoogleAuth({ secrets, fetch, openExternal }: ShellIo): GoogleAuthenticator | undefined {
  if (bundledDriveClientId.length === 0 || bundledDriveClientSecret.length === 0) return undefined;
  return new LoopbackGoogleAuthenticator({
    clientId: bundledDriveClientId,
    clientSecret: bundledDriveClientSecret,
    secrets,
    fetch,
    openBrowser: openExternal,
    listenForRedirect: listenInShell,
  });
}

/** The shell's loopback server (loopback.rs) - the page itself can't listen on a port. */
const listenInShell: ListenForRedirect = async (state, timeoutMs) => {
  let settle: ((query: URLSearchParams | undefined) => void) | undefined;
  const query = new Promise<URLSearchParams | undefined>((resolve) => {
    settle = resolve;
  });
  const onRedirect = new Channel<string | null>((target) =>
    settle?.(target === null ? undefined : new URL(target, 'http://127.0.0.1').searchParams),
  );
  const port = await invoke<number>('loopback_listen', { state, timeoutMs, onRedirect });
  return { redirectUri: `http://127.0.0.1:${port}`, query };
};
