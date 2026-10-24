import { MemoryKeyValueStore } from '@turtle-base/platform/testing';
import { expect, test } from 'vite-plus/test';

import { applyTheme, ThemeController } from './theme-controller.ts';

test('defaults to the system mode and the green preset', () => {
  const theme = new ThemeController(new MemoryKeyValueStore());

  expect([theme.mode, theme.preset]).toEqual(['system', 'green']);
});

test('remembers mode and preset in the prefs', async () => {
  const prefs = new MemoryKeyValueStore();
  const theme = new ThemeController(prefs);
  let notified = 0;
  theme.subscribe(() => notified++);

  await theme.setMode('dark');
  await theme.setPreset('violet');
  await theme.setPreset('violet');

  expect(notified).toBe(2);
  const restarted = new ThemeController(prefs);
  expect([restarted.mode, restarted.preset]).toEqual(['dark', 'violet']);
});

test('ignores stored values it does not know', async () => {
  const prefs = new MemoryKeyValueStore();
  await prefs.set('theme_mode', 'sepia');
  await prefs.set('theme_preset', 'teal');

  const theme = new ThemeController(prefs);

  expect([theme.mode, theme.preset]).toEqual(['system', 'green']);
});

test('applies the dark class and the preset', () => {
  const classes = new Set<string>();
  const attributes = new Map<string, string>();
  const target = {
    classList: { toggle: (token: string, force: boolean) => (force ? classes.add(token) : classes.delete(token)) },
    setAttribute: (name: string, value: string) => attributes.set(name, value),
  };

  applyTheme(target, { mode: 'system', preset: 'rose' }, true);
  expect([...classes]).toEqual(['dark']);
  expect(attributes.get('data-preset')).toBe('rose');

  applyTheme(target, { mode: 'light', preset: 'rose' }, true);
  expect([...classes]).toEqual([]);
});
