import { Monitor, Moon, Sun } from 'lucide-react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { themeModes, type ThemeMode } from '../../../core/theme/theme-controller.ts';
import { themePresetLabel, themePresets, type ThemePreset } from '../../../core/theme/theme-preset.ts';
import { Label } from '../../../core/ui/label.tsx';
import { ToggleGroup, ToggleGroupItem } from '../../../core/ui/toggle-group.tsx';
import { useNotifier } from '../../../core/use-notifier.ts';
import { AiSettingsSection } from '../../ai/widgets/ai-settings-section.tsx';
import { OverlayPage } from '../../shell/widgets/overlay-page.tsx';
import { SyncSettingsSection } from './sync-settings-section.tsx';

const modeLabels: Record<ThemeMode, string> = { system: 'System', light: 'Light', dark: 'Dark' };
const modeIcons: Record<ThemeMode, typeof Sun> = { system: Monitor, light: Sun, dark: Moon };

/** Device settings: the appearance, Drive sync and AI. */
export function SettingsPage({ onDone }: { onDone: () => void }) {
  const { theme } = useAppServices();
  const mode = useNotifier(theme, () => theme.mode);
  const preset = useNotifier(theme, () => theme.preset);

  return (
    <OverlayPage title="Settings" onDone={onDone}>
      <div className="grid gap-10">
        <section className="grid gap-6">
          <h2 className="text-sm font-medium text-muted-foreground">Appearance</h2>
          <div className="grid gap-2">
            <Label id="theme-mode">Theme</Label>
            <ToggleGroup
              type="single"
              variant="outline"
              aria-labelledby="theme-mode"
              value={mode}
              onValueChange={(value) => {
                const picked = themeModes.find((m) => m === value);
                if (picked !== undefined) void theme.setMode(picked);
              }}
            >
              {themeModes.map((m) => {
                const Icon = modeIcons[m];
                return (
                  <ToggleGroupItem key={m} value={m}>
                    <Icon />
                    {modeLabels[m]}
                  </ToggleGroupItem>
                );
              })}
            </ToggleGroup>
          </div>
          <div className="grid gap-2">
            <Label id="theme-preset">Accent color</Label>
            <div role="radiogroup" aria-labelledby="theme-preset" className="flex flex-wrap gap-2">
              {themePresets.map((p) => (
                <PresetSwatch key={p} preset={p} selected={p === preset} onSelect={() => void theme.setPreset(p)} />
              ))}
            </div>
          </div>
        </section>
        <AiSettingsSection />
        <SyncSettingsSection />
      </div>
    </OverlayPage>
  );
}

/** A circle in the preset's own accent - `data-preset` on the swatch scopes the color to it. */
function PresetSwatch(props: { preset: ThemePreset; selected: boolean; onSelect: () => void }) {
  const label = themePresetLabel(props.preset);
  return (
    <button
      type="button"
      role="radio"
      aria-checked={props.selected}
      aria-label={label}
      title={label}
      data-preset={props.preset}
      onClick={props.onSelect}
      className="size-8 rounded-full border-2 border-transparent bg-primary ring-offset-2 ring-offset-background aria-checked:ring-2 aria-checked:ring-primary"
    />
  );
}
