import { FileText, Pencil, Plus, Puzzle, Settings, Table2, Trash2 } from 'lucide-react';
import { useEffect, useState, type ReactNode } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { useDbQuery } from '../../../core/database/use-db-query.ts';
import type { Space } from '../../../core/database/schema.ts';
import { Button } from '../../../core/ui/button.tsx';
import { ScrollArea } from '../../../core/ui/scroll-area.tsx';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectSeparator,
  SelectTrigger,
  SelectValue,
} from '../../../core/ui/select.tsx';
import { Separator } from '../../../core/ui/separator.tsx';
import { Tooltip, TooltipContent, TooltipTrigger } from '../../../core/ui/tooltip.tsx';
import { useNotifier } from '../../../core/use-notifier.ts';
import type { AppNavigationController } from './app-navigation-controller.ts';
import { ConfirmDialog } from './confirm-dialog.tsx';
import { NamePromptDialog } from './name-prompt-dialog.tsx';

const newSpaceValue = '__new_space__';

/**
 * A select picks the current space instead of listing every space with its
 * content at once - spaces are separate areas, only one is shown at a time.
 */
export function Sidebar({ navigation }: { navigation: AppNavigationController }) {
  const { spaces } = useAppServices();
  const state = useNotifier(navigation, () => navigation.state);
  const { data: activeSpaces = [] } = useDbQuery({ tables: ['spaces'], key: [], query: () => spaces.listActive() });

  // Select the first space once spaces are loaded, if none is selected yet (or the selected one is gone). Only
  // when the spaces change: a space just created is selected before the list has caught up with it.
  useEffect(() => {
    const [first] = activeSpaces;
    const selected = navigation.state.selectedSpaceId;
    if (first !== undefined && !activeSpaces.some((space) => space.id === selected)) navigation.selectSpace(first.id);
  }, [activeSpaces, navigation]);

  return (
    <div className="flex h-full flex-col">
      <SpaceSelector spaces={activeSpaces} navigation={navigation} selectedId={state.selectedSpaceId} />
      <ScrollArea className="min-h-0 flex-1">
        {state.selectedSpaceId !== undefined && (
          <SpaceContent spaceId={state.selectedSpaceId} navigation={navigation} />
        )}
      </ScrollArea>
      {/* Fixed entries, not tied to the current space. */}
      <Separator />
      <div className="py-1">
        <SidebarRow
          icon={<Puzzle />}
          title="Plugins"
          selected={state.isShowingPlugins}
          onSelect={() => navigation.showPlugins()}
        />
        <SidebarRow
          icon={<Settings />}
          title="Settings"
          selected={state.isShowingSettings}
          onSelect={() => navigation.showSettings()}
        />
      </div>
    </div>
  );
}

function SpaceSelector(props: {
  spaces: readonly Space[];
  navigation: AppNavigationController;
  selectedId: string | undefined;
}) {
  const { spaces } = useAppServices();
  const [dialog, setDialog] = useState<'new' | 'rename' | 'delete' | undefined>();
  const selected = props.spaces.find((space) => space.id === props.selectedId);
  // Sorted for display only - the auto-selection above keeps the sidebar order.
  const sorted = props.spaces.toSorted((a, b) => a.name.localeCompare(b.name));

  return (
    <div className="flex items-center gap-1 p-2">
      <Select
        value={selected?.id ?? ''}
        onValueChange={(value) => (value === newSpaceValue ? setDialog('new') : props.navigation.selectSpace(value))}
      >
        <SelectTrigger aria-label="Space" className="min-w-0 flex-1">
          <SelectValue placeholder="Select a space" />
        </SelectTrigger>
        <SelectContent>
          {sorted.map((space) => (
            <SelectItem key={space.id} value={space.id}>
              {space.icon !== null && <span>{space.icon}</span>}
              {space.name}
            </SelectItem>
          ))}
          {sorted.length > 0 && <SelectSeparator />}
          <SelectItem value={newSpaceValue}>
            <Plus />
            New space
          </SelectItem>
        </SelectContent>
      </Select>
      {selected !== undefined && (
        <>
          <IconButton label="Rename space" onClick={() => setDialog('rename')}>
            <Pencil />
          </IconButton>
          <IconButton label="Delete space" onClick={() => setDialog('delete')}>
            <Trash2 />
          </IconButton>
        </>
      )}
      <NamePromptDialog
        open={dialog === 'new'}
        title="New space"
        confirmLabel="Create"
        onOpenChange={(open) => setDialog(open ? 'new' : undefined)}
        onSubmit={async (name) => props.navigation.selectSpace(await spaces.create({ name }))}
      />
      {selected !== undefined && (
        <>
          <NamePromptDialog
            open={dialog === 'rename'}
            title="Rename space"
            initialValue={selected.name}
            onOpenChange={(open) => setDialog(open ? 'rename' : undefined)}
            onSubmit={(name) => spaces.rename(selected.id, name)}
          />
          {/* Deleting down to zero spaces is fine - the content area then offers to create one or to sync. */}
          <ConfirmDialog
            open={dialog === 'delete'}
            title={`Delete space '${selected.name}'?`}
            message="Its collections and pages will stop being shown until it's restored - there's no trash to restore it from yet."
            onOpenChange={(open) => setDialog(open ? 'delete' : undefined)}
            onConfirm={() => spaces.softDelete(selected.id)}
          />
        </>
      )}
    </div>
  );
}

function SpaceContent({ spaceId, navigation }: { spaceId: string; navigation: AppNavigationController }) {
  const { collections, pages } = useAppServices();
  const state = useNotifier(navigation, () => navigation.state);
  const [creatingCollection, setCreatingCollection] = useState(false);
  const { data: spaceCollections = [] } = useDbQuery({
    tables: ['collections'],
    key: [spaceId],
    query: () => collections.listActiveInSpace(spaceId),
  });
  const { data: spacePages = [] } = useDbQuery({
    tables: ['pages'],
    key: ['top-level', spaceId],
    query: () => pages.listTopLevelInSpace(spaceId),
  });

  return (
    <div className="pb-2">
      <SectionHeader title="Collections" addLabel="New collection" onAdd={() => setCreatingCollection(true)} />
      {spaceCollections
        .toSorted((a, b) => a.name.localeCompare(b.name))
        .map((collection) => (
          <SidebarRow
            key={collection.id}
            icon={collection.icon ?? <Table2 />}
            title={collection.name}
            selected={state.selectedCollectionId === collection.id}
            onSelect={() => navigation.selectCollection(collection.id)}
          />
        ))}
      <SectionHeader
        title="Pages"
        addLabel="New page"
        onAdd={async () => navigation.selectPage(await pages.create({ spaceId }))}
      />
      {spacePages.map((page) => (
        <SidebarRow
          key={page.id}
          icon={page.icon ?? <FileText />}
          title={page.title.length === 0 ? 'Untitled' : page.title}
          selected={state.selectedPageId === page.id}
          onSelect={() => navigation.selectPage(page.id)}
        />
      ))}
      {/* No starter field: every entry already has a title - the grid's first column. */}
      <NamePromptDialog
        open={creatingCollection}
        title="New collection"
        confirmLabel="Create"
        onOpenChange={setCreatingCollection}
        onSubmit={async (name) => navigation.selectCollection(await collections.create({ spaceId, name }))}
      />
    </div>
  );
}

/** The "Collections"/"Pages" header with its "+" - small and muted, the entries carry the weight. */
function SectionHeader(props: { title: string; addLabel: string; onAdd: () => void | Promise<void> }) {
  return (
    <div className="flex items-center justify-between pt-2 pr-2 pl-4">
      <span className="text-xs font-medium text-muted-foreground">{props.title}</span>
      <IconButton label={props.addLabel} onClick={() => void props.onAdd()}>
        <Plus />
      </IconButton>
    </div>
  );
}

/**
 * A selectable sidebar entry - a collection, a page, or a fixed entry like
 * Settings. No action of its own, so every row has the same height. `icon`
 * is an emoji or a lucide icon.
 */
function SidebarRow(props: { icon: ReactNode; title: string; selected: boolean; onSelect: () => void }) {
  return (
    <div className="px-2 py-px">
      <button
        type="button"
        aria-current={props.selected ? 'page' : undefined}
        onClick={props.onSelect}
        className="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-[13px] hover:bg-accent/60 aria-[current=page]:bg-accent aria-[current=page]:text-accent-foreground [&_svg]:size-4 [&_svg]:shrink-0 [&_svg]:text-muted-foreground"
      >
        <span className="flex w-4 justify-center">{props.icon}</span>
        <span className="truncate">{props.title}</span>
      </button>
    </div>
  );
}

function IconButton(props: { label: string; onClick: () => void; children: ReactNode }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button variant="ghost" size="icon-sm" aria-label={props.label} onClick={props.onClick}>
          {props.children}
        </Button>
      </TooltipTrigger>
      <TooltipContent>{props.label}</TooltipContent>
    </Tooltip>
  );
}
