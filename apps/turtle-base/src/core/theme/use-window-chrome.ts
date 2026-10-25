import type { Platform } from '@turtle-base/platform';
import { useEffect } from 'react';

import { useNotifier } from '../use-notifier.ts';
import type { ThemeController } from './theme-controller.ts';

/**
 * Hands the page's colors to what the system draws around it (see
 * Platform.matchWindowChrome) - again whenever the theme changes. Read from
 * the applied CSS, so it's whatever the preset and mode make of them.
 */
export function useWindowChrome(platform: Platform, theme: ThemeController, dark: boolean): void {
  const preset = useNotifier(theme, () => theme.preset);
  useEffect(() => {
    const style = getComputedStyle(document.body);
    void platform.matchWindowChrome({
      dark,
      background: hexOf(style.backgroundColor),
      foreground: hexOf(style.color),
    });
  }, [platform, dark, preset]);
}

/** `#rrggbb` of any CSS color - the theme's are oklch(), which the shells don't parse. */
function hexOf(color: string): string {
  const context = new OffscreenCanvas(1, 1).getContext('2d');
  if (context === null) return '#000000';
  context.fillStyle = color;
  context.fillRect(0, 0, 1, 1);
  const [r = 0, g = 0, b = 0] = context.getImageData(0, 0, 1, 1).data;
  return `#${[r, g, b].map((channel) => channel.toString(16).padStart(2, '0')).join('')}`;
}
