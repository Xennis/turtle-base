import type { KeyValueStore } from '@turtle-base/platform';

import { Notifier } from '../notifier.ts';
import { defaultThemePreset, isThemePreset, type ThemePreset } from './theme-preset.ts';

export const themeModes = ['system', 'light', 'dark'] as const;

export type ThemeMode = (typeof themeModes)[number];

const modeKey = 'theme_mode';
const presetKey = 'theme_preset';

/**
 * The user's theme mode and accent color, stored per device in the prefs
 * rather than in the synced database - a display setting for this device,
 * not content to sync.
 */
export class ThemeController extends Notifier {
  readonly #prefs: KeyValueStore;
  #mode: ThemeMode;
  #preset: ThemePreset;

  constructor(prefs: KeyValueStore) {
    super();
    this.#prefs = prefs;
    const mode = prefs.get(modeKey);
    this.#mode = themeModes.find((m) => m === mode) ?? 'system';
    const preset = prefs.get(presetKey);
    this.#preset = isThemePreset(preset) ? preset : defaultThemePreset;
  }

  get mode(): ThemeMode {
    return this.#mode;
  }

  get preset(): ThemePreset {
    return this.#preset;
  }

  async setMode(mode: ThemeMode): Promise<void> {
    if (mode === this.#mode) return;
    this.#mode = mode;
    this.notify();
    await this.#prefs.set(modeKey, mode);
  }

  async setPreset(preset: ThemePreset): Promise<void> {
    if (preset === this.#preset) return;
    this.#preset = preset;
    this.notify();
    await this.#prefs.set(presetKey, preset);
  }
}

/** The parts of `<html>` the theme is set on - a narrow type, so it can be checked without a DOM. */
export interface ThemeTarget {
  readonly classList: { toggle(token: string, force: boolean): unknown };
  setAttribute(name: string, value: string): void;
}

/** Sets the `dark` class and `data-preset` styles.css reads. `systemDark` decides for mode `system`. */
export function applyTheme(target: ThemeTarget, theme: { mode: ThemeMode; preset: ThemePreset }, systemDark: boolean) {
  target.classList.toggle('dark', theme.mode === 'dark' || (theme.mode === 'system' && systemDark));
  target.setAttribute('data-preset', theme.preset);
}
