import { desktopFileScheme } from './ipc-contract.ts';

/**
 * What the app's page may load, the same in both shells: Electron sends it
 * as a header, the production build also writes it into index.html (a meta
 * tag, for Capacitor - and not in development, where Vite's hot reload needs
 * inline scripts). On Android everything of the app, its files included,
 * comes from Capacitor's local server - 'self'.
 */
export const contentSecurityPolicy = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  // https: for remote pictures like a lookup's covers - only shown, never sent anything.
  `img-src 'self' data: blob: https: ${desktopFileScheme}:`,
  `media-src 'self' blob: ${desktopFileScheme}:`,
  // Requests to the internet go through the shell (Platform.fetch), never from the page.
  "connect-src 'self'",
].join('; ');
