import { QueryClient } from '@tanstack/react-query';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';

import { App } from './app.tsx';
import { createAppServices } from './core/app-scope.tsx';
import { AppDatabase } from './core/database/app-database.ts';
import { invalidateTables } from './core/database/use-db-query.ts';
import { createElectronPlatform } from './core/platform/electron-platform.ts';
import { applyTheme, ThemeController } from './core/theme/theme-controller.ts';
import './styles.css';

const bridge = window.turtleDesktop;
if (bridge === undefined) throw new Error('Not running in the desktop shell (no window.turtleDesktop)');

const platform = await createElectronPlatform(bridge);
const theme = new ThemeController(platform.prefs);
// Before the first render, so the window doesn't flash in the wrong theme.
applyTheme(document.documentElement, theme, matchMedia('(prefers-color-scheme: dark)').matches);

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
    <App services={createAppServices(platform, database, theme)} queryClient={queryClient} />
  </StrictMode>,
);
