import { useQuery } from '@tanstack/react-query';
import type { TurtlePlugin } from '@turtle-base/plugin-api';
import type { Catalog, CatalogEntry } from '@turtle-base/plugin-catalog';
import { Download, Plus, RefreshCw, Trash2 } from 'lucide-react';
import { useState, type ReactNode } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { useDbQuery } from '../../../core/database/use-db-query.ts';
import { Badge } from '../../../core/ui/badge.tsx';
import { Button } from '../../../core/ui/button.tsx';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '../../../core/ui/card.tsx';
import { Input } from '../../../core/ui/input.tsx';
import { ConfirmDialog } from '../../shell/widgets/confirm-dialog.tsx';
import { OverlayPage } from '../../shell/widgets/overlay-page.tsx';
import type { InstalledPlugin } from '../data/installed-plugins-repository.ts';
import type { PluginCandidate } from '../data/plugin-installer.ts';
import { PluginInstallDialog } from './plugin-install-dialog.tsx';

/** Installing, updating or removing a plugin takes effect on a fresh start of the page. */
function reloadApp() {
  location.reload();
}

/**
 * The installed plugins, the catalog's others, and installing one from any
 * URL. Adding an installed plugin creates a space with its collections -
 * adding it again creates another, e.g. a second reading list.
 */
export function PluginsPage({ onDone, onOpenSpace }: { onDone: () => void; onOpenSpace: (spaceId: string) => void }) {
  const { installedPlugins, pluginInstaller } = useAppServices();
  const [candidate, setCandidate] = useState<PluginCandidate | undefined>();
  const [cachedCatalog] = useState(() => pluginInstaller.cachedCatalog());
  const catalog = useQuery({
    queryKey: ['plugin-catalog'],
    queryFn: () => pluginInstaller.refreshCatalog(),
    ...(cachedCatalog === undefined ? {} : { placeholderData: cachedCatalog }),
    retry: false,
  });
  const installed = [...installedPlugins.loaded, ...installedPlugins.broken];
  const installedIds = new Set(installed.map(({ installed: { manifest } }) => manifest.id));
  const available = (catalog.data?.plugins ?? []).filter((entry) => !installedIds.has(entry.id));

  return (
    <OverlayPage title="Plugins" onDone={onDone}>
      <div className="grid gap-10">
        {installed.length > 0 && (
          <Section title="Installed">
            {installedPlugins.loaded.map(({ installed: plugin, plugin: loaded }) => (
              <InstalledCard
                key={plugin.manifest.id}
                installed={plugin}
                plugin={loaded}
                catalog={catalog.data}
                onOpenSpace={onOpenSpace}
                onUpdate={setCandidate}
              />
            ))}
            {installedPlugins.broken.map(({ installed: plugin, error }) => (
              <InstalledCard
                key={plugin.manifest.id}
                installed={plugin}
                error={error}
                catalog={catalog.data}
                onOpenSpace={onOpenSpace}
                onUpdate={setCandidate}
              />
            ))}
          </Section>
        )}
        <Section title="Catalog">
          {catalog.isError && (
            <p className="text-sm text-destructive">
              Couldn't load the catalog{catalog.data === undefined ? '' : ' - showing it as last loaded'}.
            </p>
          )}
          {catalog.data === undefined && catalog.isPending && <p className="text-muted-foreground">Loading…</p>}
          {catalog.data !== undefined && available.length === 0 && (
            <p className="text-muted-foreground">
              {catalog.data.plugins.length === 0 ? 'No plugins yet.' : 'All plugins are installed.'}
            </p>
          )}
          {available.map((entry) => (
            <CatalogCard key={entry.id} entry={entry} onInstall={setCandidate} />
          ))}
        </Section>
        <Section title="Install from URL">
          <UrlInstall catalog={catalog.data} onCandidate={setCandidate} />
        </Section>
      </div>
      {candidate !== undefined && (
        <PluginInstallDialog
          candidate={candidate}
          onOpenChange={(open) => !open && setCandidate(undefined)}
          onInstalled={reloadApp}
        />
      )}
    </OverlayPage>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="grid gap-4">
      <h2 className="text-sm font-medium text-muted-foreground">{title}</h2>
      {children}
    </section>
  );
}

function PluginTitle({ icon, name }: { icon: string | undefined; name: string }) {
  return (
    <CardTitle>
      {icon !== undefined && <span className="mr-2">{icon}</span>}
      {name}
    </CardTitle>
  );
}

function InstalledCard(props: {
  installed: InstalledPlugin;
  plugin?: TurtlePlugin;
  error?: string;
  catalog: Catalog | undefined;
  onOpenSpace: (spaceId: string) => void;
  onUpdate: (candidate: PluginCandidate) => void;
}) {
  const { pluginInstances, pluginInstaller } = useAppServices();
  const { installed, plugin, catalog } = props;
  const { manifest } = installed;
  const [adding, setAdding] = useState(false);
  const [removing, setRemoving] = useState(false);
  const { data: instances = [] } = useDbQuery({
    tables: ['spaces'],
    key: ['plugin', manifest.id],
    query: () => pluginInstances.listInstances(manifest.id),
  });
  const update = useQuery({
    queryKey: ['plugin-update', manifest.id, manifest.version, catalog],
    queryFn: async () => (await pluginInstaller.updateOf(installed, catalog)) ?? null,
    retry: false,
  });
  const updateTo = update.data ?? undefined;
  const collections = (plugin?.collections ?? []).map((collection) => collection.name).join(', ');

  async function add() {
    if (plugin === undefined) return;
    setAdding(true);
    try {
      props.onOpenSpace(await pluginInstances.add(plugin));
    } finally {
      setAdding(false);
    }
  }

  async function remove() {
    await pluginInstaller.remove(manifest.id);
    reloadApp();
  }

  return (
    <Card>
      <CardHeader className="grid gap-1.5">
        <div className="flex flex-wrap items-center gap-2">
          <PluginTitle icon={manifest.icon} name={manifest.name} />
          <Badge variant="outline">{manifest.version}</Badge>
          {!installed.fromCatalog && <Badge variant="destructive">Not reviewed</Badge>}
        </div>
        <CardDescription>{manifest.description}</CardDescription>
        {collections.length > 0 && (
          <CardDescription>
            Creates a space "{manifest.name}" with: {collections}
          </CardDescription>
        )}
        <Reaches hosts={manifest.permissions.network ?? []} />
        {props.error !== undefined && <p className="text-sm text-destructive">Didn't load: {props.error}</p>}
      </CardHeader>
      <CardContent className="grid gap-3">
        {instances.length > 0 && (
          <div className="flex flex-wrap gap-2">
            {instances.map((space) => (
              <Button key={space.id} variant="outline" size="sm" onClick={() => props.onOpenSpace(space.id)}>
                {[space.icon, space.name].filter((part) => part !== null).join(' ')}
              </Button>
            ))}
          </div>
        )}
        <div className="flex flex-wrap gap-2">
          {plugin !== undefined && collections.length > 0 && (
            <Button disabled={adding} onClick={() => void add()}>
              <Plus />
              Add
            </Button>
          )}
          {updateTo !== undefined && (
            <Button variant="secondary" onClick={() => props.onUpdate(updateTo)}>
              <RefreshCw />
              Update to {updateTo.manifest.version}
            </Button>
          )}
          <Button variant="ghost" onClick={() => setRemoving(true)}>
            <Trash2 />
            Remove
          </Button>
        </div>
        {update.isError && <p className="text-sm text-muted-foreground">Couldn't look for updates.</p>}
      </CardContent>
      <ConfirmDialog
        open={removing}
        title={`Remove ${manifest.name}?`}
        message={`Its spaces stay, as ordinary spaces - without what ${manifest.name} adds to them.`}
        confirmLabel="Remove"
        onOpenChange={setRemoving}
        onConfirm={remove}
      />
    </Card>
  );
}

function CatalogCard({ entry, onInstall }: { entry: CatalogEntry; onInstall: (candidate: PluginCandidate) => void }) {
  const { pluginInstaller } = useAppServices();
  const [checking, setChecking] = useState(false);
  const [error, setError] = useState<string | undefined>();

  async function install() {
    setChecking(true);
    setError(undefined);
    try {
      onInstall(await pluginInstaller.fromCatalog(entry));
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : String(failure));
    } finally {
      setChecking(false);
    }
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-start gap-2">
        <div className="grid flex-1 gap-1.5">
          <div className="flex flex-wrap items-center gap-2">
            <PluginTitle icon={entry.icon} name={entry.name} />
            <Badge variant="outline">{entry.version}</Badge>
          </div>
          <CardDescription>{entry.description}</CardDescription>
          <CardDescription>By {entry.author}</CardDescription>
          {error !== undefined && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <Button disabled={checking} onClick={() => void install()}>
          <Download />
          Install
        </Button>
      </CardHeader>
    </Card>
  );
}

function UrlInstall(props: { catalog: Catalog | undefined; onCandidate: (candidate: PluginCandidate) => void }) {
  const { pluginInstaller } = useAppServices();
  const [url, setUrl] = useState('');
  const [checking, setChecking] = useState(false);
  const [error, setError] = useState<string | undefined>();

  async function check() {
    setChecking(true);
    setError(undefined);
    try {
      props.onCandidate(await pluginInstaller.fromUrl(url, props.catalog));
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : String(failure));
    } finally {
      setChecking(false);
    }
  }

  return (
    <form
      className="grid gap-2"
      onSubmit={(event) => {
        event.preventDefault();
        void check();
      }}
    >
      <p className="text-sm text-muted-foreground">
        The https URL of a plugin's manifest.json. Plugins from outside the catalog aren't checked by anyone.
      </p>
      <div className="flex gap-2">
        <Input
          aria-label="Manifest URL"
          placeholder="https://example.org/plugin/manifest.json"
          value={url}
          onChange={(event) => setUrl(event.target.value)}
        />
        <Button type="submit" variant="outline" disabled={checking || url.trim().length === 0}>
          Install…
        </Button>
      </div>
      {error !== undefined && <p className="text-sm text-destructive">{error}</p>}
    </form>
  );
}

function Reaches({ hosts }: { hosts: readonly string[] }) {
  return (
    <CardDescription>
      {hosts.length === 0 ? 'Reaches nothing on the internet' : `Reaches ${hosts.join(', ')}`}
    </CardDescription>
  );
}
