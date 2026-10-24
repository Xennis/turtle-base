import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';

import { AppScope } from './core/app-scope.tsx';
import { AppDatabase } from './core/database/app-database.ts';
import { invalidateTables } from './core/database/use-db-query.ts';
import { createElectronPlatform } from './core/platform/electron-platform.ts';
import { SpacesPage } from './features/spaces/widgets/spaces-page.tsx';
import './styles.css';

const bridge = window.turtleDesktop;
if (bridge === undefined) throw new Error('Not running in the desktop shell (no window.turtleDesktop)');

const platform = await createElectronPlatform(bridge);
const queryClient = new QueryClient();
const database = await AppDatabase.open({
  sql: platform.sql,
  prefs: platform.prefs,
  onTablesChanged: (tables) => invalidateTables(queryClient, tables),
});

const root = document.getElementById('root');
if (root === null) throw new Error('No #root element');
createRoot(root).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <AppScope services={{ database }}>
        <SpacesPage />
      </AppScope>
    </QueryClientProvider>
  </StrictMode>,
);
