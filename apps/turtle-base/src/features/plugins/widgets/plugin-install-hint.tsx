import { useQuery } from '@tanstack/react-query';
import { Puzzle } from 'lucide-react';
import { useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { Button } from '../../../core/ui/button.tsx';
import { isPluginCollectionId, pluginIdOf } from '../data/plugin-registry.ts';

/**
 * On a collection a catalog plugin created that isn't installed on this
 * device - e.g. one that came through sync. The collection works without
 * it, only what the plugin adds is missing.
 */
export function PluginInstallHint(props: { collectionId: string; onShowPlugins: () => void }) {
  const { installedPlugins, pluginInstaller } = useAppServices();
  const pluginId = pluginIdOf(props.collectionId);
  const missing = isPluginCollectionId(props.collectionId) && installedPlugins.byId(pluginId) === undefined;
  const [cachedCatalog] = useState(() => pluginInstaller.cachedCatalog());
  const { data: catalog } = useQuery({
    queryKey: ['plugin-catalog'],
    queryFn: () => pluginInstaller.refreshCatalog(),
    ...(cachedCatalog === undefined ? {} : { placeholderData: cachedCatalog }),
    enabled: missing,
    retry: false,
  });
  const entry = missing ? catalog?.plugins.find((plugin) => plugin.id === pluginId) : undefined;
  if (entry === undefined) return null;
  return (
    <div className="flex flex-wrap items-center gap-2 rounded-md border bg-muted/50 px-3 py-2 text-sm">
      <Puzzle className="size-4 text-muted-foreground" />
      <span className="flex-1">
        Created by plugin {entry.icon} {entry.name}, which isn't installed on this device.
      </span>
      <Button size="sm" variant="outline" onClick={props.onShowPlugins}>
        Install
      </Button>
    </div>
  );
}
