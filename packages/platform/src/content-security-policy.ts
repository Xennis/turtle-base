/** Tauri's asset protocol, which serves the attachment files: `asset://localhost` on the desktop, `http://asset.localhost` on Android. */
const tauriAssets = 'asset: http://asset.localhost';

/**
 * What the app's page may load, on the desktop and on Android alike. The
 * production build writes it into index.html as a meta tag - not in
 * development, where Vite's hot reload needs inline scripts.
 */
export const contentSecurityPolicy = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  // https: for remote pictures like a lookup's covers - only shown, never sent anything.
  `img-src 'self' data: blob: https: ${tauriAssets}`,
  `media-src 'self' blob: ${tauriAssets}`,
  // Requests to the internet go through the shell (Platform.fetch), never from the page - only Tauri's IPC.
  "connect-src 'self' ipc: http://ipc.localhost",
].join('; ');
