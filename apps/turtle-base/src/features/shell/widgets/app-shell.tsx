import { ArrowLeft, FileText, LayoutDashboard, Layers, Menu } from 'lucide-react';
import { useEffect, useState, type ReactNode } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { useDbQuery } from '../../../core/database/use-db-query.ts';
import { Button } from '../../../core/ui/button.tsx';
import { Sheet, SheetContent, SheetTitle } from '../../../core/ui/sheet.tsx';
import { useMediaQuery } from '../../../core/use-media-query.ts';
import { useNotifier } from '../../../core/use-notifier.ts';
import { PluginsPage } from '../../plugins/widgets/plugins-page.tsx';
import { SettingsPage } from '../../settings/widgets/settings-page.tsx';
import { CollectionEditPage } from '../../tables/widgets/collection-edit-page.tsx';
import { CollectionView } from '../../tables/widgets/collection-view.tsx';
import { AppNavigationController } from './app-navigation-controller.ts';
import { NamePromptDialog } from './name-prompt-dialog.tsx';
import { Sidebar } from './sidebar.tsx';

/**
 * Wide windows: the sidebar floats as a card next to the content. Narrow
 * ones (phones): the sidebar is a drawer, and navigation is list-then-detail
 * with a back button. The breakpoint is the common one between phone and
 * tablet widths.
 */
export function AppShell() {
  const [navigation] = useState(() => new AppNavigationController());
  const isWide = useMediaQuery('(min-width: 600px)');
  return isWide ? <WideShell navigation={navigation} /> : <NarrowShell navigation={navigation} />;
}

function WideShell({ navigation }: { navigation: AppNavigationController }) {
  return (
    <div className="flex h-screen">
      <aside className="m-2 mr-0 w-[300px] shrink-0 overflow-hidden rounded-xl border bg-sidebar text-sidebar-foreground">
        <Sidebar navigation={navigation} />
      </aside>
      <main className="min-w-0 flex-1 overflow-auto">
        <MainContent navigation={navigation} />
      </main>
    </div>
  );
}

function NarrowShell({ navigation }: { navigation: AppNavigationController }) {
  const state = useNotifier(navigation, () => navigation.state);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const hasSelection = state.selectedCollectionId !== undefined || state.selectedPageId !== undefined;
  const showsOverlay = navigation.isShowingOverlayPage;

  // A selection made in the drawer closes it.
  useEffect(
    () =>
      navigation.subscribe(() => {
        const { selectedCollectionId, selectedPageId } = navigation.state;
        if (selectedCollectionId !== undefined || selectedPageId !== undefined || navigation.isShowingOverlayPage) {
          setDrawerOpen(false);
        }
      }),
    [navigation],
  );

  return (
    <div className="flex h-screen flex-col">
      {!showsOverlay && (
        <header className="flex h-12 shrink-0 items-center gap-2 border-b px-2">
          {hasSelection ? (
            <Button variant="ghost" size="icon" aria-label="Back" onClick={() => navigation.clearSelection()}>
              <ArrowLeft />
            </Button>
          ) : (
            <Button variant="ghost" size="icon" aria-label="Open sidebar" onClick={() => setDrawerOpen(true)}>
              <Menu />
            </Button>
          )}
          <span className="font-medium">Turtle Base</span>
        </header>
      )}
      <main className="min-h-0 flex-1 overflow-auto">
        <MainContent navigation={navigation} />
      </main>
      <Sheet open={drawerOpen} onOpenChange={setDrawerOpen}>
        <SheetContent side="left" className="w-[300px] p-0" showCloseButton={false}>
          <SheetTitle className="sr-only">Sidebar</SheetTitle>
          <Sidebar navigation={navigation} />
        </SheetContent>
      </Sheet>
    </div>
  );
}

function MainContent({ navigation }: { navigation: AppNavigationController }) {
  const state = useNotifier(navigation, () => navigation.state);
  if (state.isShowingSettings) return <SettingsPage onDone={() => navigation.hideSettings()} />;
  if (state.isShowingPlugins) return <PluginsPage onDone={() => navigation.hidePlugins()} />;
  if (state.selectedCollectionId !== undefined) {
    return state.isEditingCollection ? (
      <CollectionEditPage
        collectionId={state.selectedCollectionId}
        onDone={() => navigation.stopEditingCollection()}
        onDeleted={() => navigation.clearSelection()}
      />
    ) : (
      <CollectionView
        collectionId={state.selectedCollectionId}
        onEdit={() => navigation.startEditingCollection()}
        onOpenEntry={(pageId) => navigation.selectPage(pageId)}
      />
    );
  }
  if (state.selectedPageId !== undefined) return <PagePlaceholder pageId={state.selectedPageId} />;
  return <NothingSelected navigation={navigation} />;
}

/**
 * No spaces at all isn't necessarily "starting from scratch" - it may be a
 * fresh install about to sync in existing spaces, so both are offered.
 */
function NothingSelected({ navigation }: { navigation: AppNavigationController }) {
  const { spaces } = useAppServices();
  const [creating, setCreating] = useState(false);
  const { data } = useDbQuery({ tables: ['spaces'], key: [], query: () => spaces.listActive() });
  if (data === undefined) return null;
  if (data.length > 0) {
    return (
      <Centered icon={<LayoutDashboard />}>
        <p>Select a collection or page</p>
      </Centered>
    );
  }
  return (
    <Centered icon={<Layers />}>
      <p>No spaces yet</p>
      <div className="mt-4 flex flex-col gap-2">
        <Button onClick={() => setCreating(true)}>Create your first space</Button>
        <Button variant="outline" onClick={() => navigation.showSettings()}>
          Go to Settings to sync
        </Button>
      </div>
      <NamePromptDialog
        open={creating}
        title="New space"
        confirmLabel="Create"
        onOpenChange={setCreating}
        onSubmit={async (name) => navigation.selectSpace(await spaces.create({ name }))}
      />
    </Centered>
  );
}

/** Stands in for the page view until it's ported. */
function PagePlaceholder({ pageId }: { pageId: string }) {
  const { pages } = useAppServices();
  const { data } = useDbQuery({ tables: ['pages'], key: [pageId], query: () => pages.byId(pageId) });
  const title = data?.title ?? '';
  return (
    <Centered icon={data?.icon ?? <FileText />}>
      <p className="text-lg text-foreground">{title.length === 0 ? 'Untitled' : title}</p>
      <p>The page editor is ported next.</p>
    </Centered>
  );
}

function Centered({ icon, children }: { icon: ReactNode; children: ReactNode }) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-2 p-6 text-center text-muted-foreground [&>svg]:size-10">
      <div className="text-4xl [&_svg]:size-10">{icon}</div>
      {children}
    </div>
  );
}
