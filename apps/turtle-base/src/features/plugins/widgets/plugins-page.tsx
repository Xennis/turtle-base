import type { TurtlePlugin } from '@turtle-base/plugin-api';
import { Plus } from 'lucide-react';
import { useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { useDbQuery } from '../../../core/database/use-db-query.ts';
import { Button } from '../../../core/ui/button.tsx';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '../../../core/ui/card.tsx';
import { OverlayPage } from '../../shell/widgets/overlay-page.tsx';

/**
 * The plugins the app ships with. Adding one creates a space with its
 * collections - adding it again creates another, e.g. a second reading list.
 */
export function PluginsPage({ onDone, onOpenSpace }: { onDone: () => void; onOpenSpace: (spaceId: string) => void }) {
  const { plugins } = useAppServices();
  return (
    <OverlayPage title="Plugins" onDone={onDone}>
      <div className="grid gap-4">
        {plugins.addable.length === 0 && <p className="text-muted-foreground">No plugins available.</p>}
        {plugins.addable.map((plugin) => (
          <PluginCard key={plugin.id} plugin={plugin} onOpenSpace={onOpenSpace} />
        ))}
      </div>
    </OverlayPage>
  );
}

function PluginCard({ plugin, onOpenSpace }: { plugin: TurtlePlugin; onOpenSpace: (spaceId: string) => void }) {
  const { pluginInstances } = useAppServices();
  const [adding, setAdding] = useState(false);
  const { data: instances = [] } = useDbQuery({
    tables: ['spaces'],
    key: ['plugin', plugin.id],
    query: () => pluginInstances.listInstances(plugin.id),
  });
  const collections = (plugin.collections ?? []).map((collection) => collection.name).join(', ');

  async function add() {
    setAdding(true);
    try {
      onOpenSpace(await pluginInstances.add(plugin));
    } finally {
      setAdding(false);
    }
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-start gap-2">
        <div className="grid flex-1 gap-1.5">
          <CardTitle>
            {plugin.icon !== undefined && <span className="mr-2">{plugin.icon}</span>}
            {plugin.name}
          </CardTitle>
          <CardDescription>{plugin.description}</CardDescription>
          <CardDescription>
            Creates a space "{plugin.name}" with: {collections}
          </CardDescription>
        </div>
        <Button disabled={adding} onClick={() => void add()}>
          <Plus />
          Add
        </Button>
      </CardHeader>
      {instances.length > 0 && (
        <CardContent className="flex flex-wrap gap-2">
          {instances.map((space) => (
            <Button key={space.id} variant="outline" size="sm" onClick={() => onOpenSpace(space.id)}>
              {[space.icon, space.name].filter((part) => part !== null).join(' ')}
            </Button>
          ))}
        </CardContent>
      )}
    </Card>
  );
}
