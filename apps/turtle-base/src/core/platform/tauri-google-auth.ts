import { Channel, invoke } from '@tauri-apps/api/core';
import { fetch as shellFetch } from '@tauri-apps/plugin-http';
import { openUrl } from '@tauri-apps/plugin-opener';
import { type ListenForRedirect, LoopbackGoogleAuthenticator } from '@turtle-base/crdt-file-sync-google-drive';
import type { GoogleAuthenticator, SecretStorage } from '@turtle-base/platform';

/**
 * Google sign-in on the desktop: the loopback flow in the user's browser,
 * with the "Desktop app" OAuth client the build was given (see vite.config.ts).
 * Undefined without one - the app then hides Drive sync.
 */
export function desktopGoogleAuth(secrets: SecretStorage): GoogleAuthenticator | undefined {
  if (bundledDriveClientId.length === 0 || bundledDriveClientSecret.length === 0) return undefined;
  return new LoopbackGoogleAuthenticator({
    clientId: bundledDriveClientId,
    clientSecret: bundledDriveClientSecret,
    secrets,
    fetch: shellFetch,
    openBrowser: (url) => openUrl(url),
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
