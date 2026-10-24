import { useEffect } from 'react';

import { useMediaQuery } from '../use-media-query.ts';
import { useNotifier } from '../use-notifier.ts';
import { applyTheme, type ThemeController } from './theme-controller.ts';

/** Keeps `<html>` on the user's theme - and, in mode `system`, on the system's. */
export function useAppliedTheme(theme: ThemeController): void {
  const mode = useNotifier(theme, () => theme.mode);
  const preset = useNotifier(theme, () => theme.preset);
  const systemDark = useMediaQuery('(prefers-color-scheme: dark)');
  useEffect(() => applyTheme(document.documentElement, { mode, preset }, systemDark), [mode, preset, systemDark]);
}
