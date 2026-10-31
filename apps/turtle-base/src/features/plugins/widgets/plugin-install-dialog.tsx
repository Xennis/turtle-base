import { TriangleAlert } from 'lucide-react';
import { useId, useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { Badge } from '../../../core/ui/badge.tsx';
import { Button } from '../../../core/ui/button.tsx';
import { Checkbox } from '../../../core/ui/checkbox.tsx';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '../../../core/ui/dialog.tsx';
import { Label } from '../../../core/ui/label.tsx';
import type { PluginCandidate } from '../data/plugin-installer.ts';

/**
 * Shows what installing `candidate` means - where it's from and what it may
 * reach - and installs it once confirmed. A plugin from a URL runs with the
 * app's rights, so the user has to tick that they trust its author. The
 * page reloads after installing, which is when the plugin takes effect.
 */
export function PluginInstallDialog(props: {
  candidate: PluginCandidate;
  onOpenChange: (open: boolean) => void;
  onInstalled: () => void;
}) {
  const { pluginInstaller } = useAppServices();
  const { candidate } = props;
  const { manifest, replaces } = candidate;
  const [trusted, setTrusted] = useState(candidate.fromCatalog);
  const [installing, setInstalling] = useState(false);
  const [error, setError] = useState<string | undefined>();
  const trustId = useId();
  const hosts = manifest.permissions.network ?? [];
  const knownHosts = new Set(replaces?.manifest.permissions.network ?? []);

  async function install() {
    setInstalling(true);
    setError(undefined);
    try {
      await pluginInstaller.install(candidate);
      props.onInstalled();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : String(failure));
      setInstalling(false);
    }
  }

  return (
    <Dialog open onOpenChange={props.onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>
            {replaces === undefined ? 'Install' : 'Update'} {manifest.icon} {manifest.name}
          </DialogTitle>
          <DialogDescription>
            Version {manifest.version}
            {replaces === undefined ? '' : ` (installed: ${replaces.manifest.version})`} by {manifest.author}
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-4 text-sm">
          <p>{manifest.description}</p>
          <div className="grid gap-1">
            <span className="font-medium">Reaches</span>
            {hosts.length === 0 ? (
              <span className="text-muted-foreground">Nothing on the internet</span>
            ) : (
              <ul className="flex flex-wrap gap-1.5">
                {hosts.map((host) => (
                  <li key={host}>
                    <Badge variant={replaces === undefined || knownHosts.has(host) ? 'secondary' : 'default'}>
                      {host}
                      {replaces !== undefined && !knownHosts.has(host) && ' (new)'}
                    </Badge>
                  </li>
                ))}
              </ul>
            )}
          </div>
          {candidate.fromCatalog ? (
            <p className="text-muted-foreground">From the plugin catalog.</p>
          ) : (
            <div className="grid gap-3 rounded-md border border-destructive/50 bg-destructive/10 p-3">
              <p className="flex gap-2 font-medium text-destructive">
                <TriangleAlert className="size-4 shrink-0 translate-y-0.5" />
                Not in the catalog - nobody has checked this plugin.
              </p>
              <p>
                It runs with the same rights as the app: it can read and change all your data, use your Google Drive
                connection and your AI keys, and send any of it to the internet. Install it only if you trust its
                author.
              </p>
              <p className="break-all text-muted-foreground">From {candidate.manifestUrl}</p>
              <div className="flex items-center gap-2">
                <Checkbox id={trustId} checked={trusted} onCheckedChange={(checked) => setTrusted(checked === true)} />
                <Label htmlFor={trustId}>I trust {manifest.author} with all my data</Label>
              </div>
            </div>
          )}
          {error !== undefined && <p className="text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => props.onOpenChange(false)}>
            Cancel
          </Button>
          <Button disabled={!trusted || installing} onClick={() => void install()}>
            {installing ? 'Installing…' : replaces === undefined ? 'Install' : 'Update'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
