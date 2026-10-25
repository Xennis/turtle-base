import type { BrowserWindow, BrowserWindowConstructorOptions } from 'electron';

/** The title bar the page draws (see the app's WindowTitleBar) - the window's buttons sit on it. */
const titleBarHeight = 36;

/**
 * No system title bar: the page draws its own in the theme's colors, with the
 * system's window buttons on top (on macOS the traffic lights, which follow
 * the system's appearance by themselves).
 */
export const titleBarOptions: BrowserWindowConstructorOptions = {
  titleBarStyle: 'hidden',
  titleBarOverlay: { height: titleBarHeight },
  ...(process.platform === 'darwin' ? { trafficLightPosition: { x: 12, y: 11 } } : {}),
};

/** Colors the window buttons like the page's title bar - Linux and Windows; macOS has no such setting. */
export function matchTitleBar(window: BrowserWindow, background: string, foreground: string): void {
  if (process.platform === 'darwin') return;
  window.setTitleBarOverlay({ color: background, symbolColor: foreground, height: titleBarHeight });
}
