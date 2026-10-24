/**
 * The accent color the user picked - shadcn's base colors and themes. Each
 * one is a `data-preset` block in styles.css; the neutrals stay the same.
 */
export const themePresets = [
  'blue',
  'gray',
  'green',
  'neutral',
  'orange',
  'red',
  'rose',
  'slate',
  'stone',
  'violet',
  'yellow',
  'zinc',
] as const;

export type ThemePreset = (typeof themePresets)[number];

/** The Flutter app's original color, kept as the default. */
export const defaultThemePreset: ThemePreset = 'green';

export function themePresetLabel(preset: ThemePreset): string {
  return preset.charAt(0).toUpperCase() + preset.slice(1);
}

export function isThemePreset(value: string | undefined): value is ThemePreset {
  return themePresets.some((preset) => preset === value);
}
