import { OverlayPage } from '../../shell/widgets/overlay-page.tsx';

/** Placeholder until the plugins page is ported - the data side (adding a plugin as a space) already is. */
export function PluginsPage({ onDone }: { onDone: () => void }) {
  return (
    <OverlayPage title="Plugins" onDone={onDone}>
      <p className="text-muted-foreground">The plugins page is ported next.</p>
    </OverlayPage>
  );
}
