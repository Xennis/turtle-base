import { useMediaQuery } from '../use-media-query.ts';
import { useNotifier } from '../use-notifier.ts';
import type { ThemeController } from './theme-controller.ts';

/** Whether the app shows dark right now - for components that take a theme prop rather than reading the CSS. */
export function useIsDark(theme: ThemeController): boolean {
  const mode = useNotifier(theme, () => theme.mode);
  const systemDark = useMediaQuery('(prefers-color-scheme: dark)');
  return mode === 'dark' || (mode === 'system' && systemDark);
}
