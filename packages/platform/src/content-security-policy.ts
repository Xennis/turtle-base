import { desktopFileScheme } from './ipc-contract.ts';

/** Tauri's asset protocol, which serves the attachment files: `asset://localhost` on the desktop, `http://asset.localhost` on Android. */
const tauriAssets = 'asset: http://asset.localhost';

/**
 * What the app's page may load, the same in every shell: Electron sends it
 * as a header, the production build also writes it into index.html (a meta
 * tag, for Tauri and Capacitor - and not in development, where Vite's hot
 * reload needs inline scripts). On Android everything of the app, its files
 * included, comes from Capacitor's local server - 'self'.
 */
export const contentSecurityPolicy = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  // https: for remote pictures like a lookup's covers - only shown, never sent anything.
  `img-src 'self' data: blob: https: ${desktopFileScheme}: ${tauriAssets}`,
  `media-src 'self' blob: ${desktopFileScheme}: ${tauriAssets}`,
  // Requests to the internet go through the shell (Platform.fetch), never from the page - only Tauri's IPC.
  "connect-src 'self' ipc: http://ipc.localhost",
].join('; ');
