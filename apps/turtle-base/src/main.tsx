import { QueryClient } from '@tanstack/react-query';
import { isTauri } from '@tauri-apps/api/core';
import type { Platform } from '@turtle-base/platform';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';

import { App } from './app.tsx';
import { createAppServices } from './core/app-scope.tsx';
import { AppDatabase } from './core/database/app-database.ts';
import { invalidateTables } from './core/database/use-db-query.ts';
import { applyTheme, ThemeController } from './core/theme/theme-controller.ts';
import { InstalledPluginsRepository } from './features/plugins/data/installed-plugins-repository.ts';
import { InstalledPlugins } from './features/plugins/data/installed-plugins.ts';
import { pagePluginLoader } from './features/plugins/data/plugin-loader.ts';
import './styles.css';

/** The shell's platform - the page only runs in the Tauri shell (apps/shell). */
async function createPlatform(): Promise<Platform> {
  if (!isTauri()) throw new Error('Not running in the Tauri shell');
  return (await import('./core/platform/tauri-platform.ts')).createTauriPlatform();
}

const platform = await createPlatform();
const theme = new ThemeController(platform.prefs);
// Before the first render, so the window doesn't flash in the wrong theme.
applyTheme(document.documentElement, theme, matchMedia('(prefers-color-scheme: dark)').matches);

const queryClient = new QueryClient();
const [database, installedPlugins] = await Promise.all([
  AppDatabase.open({
    sql: platform.sql,
    prefs: platform.prefs,
    onTablesChanged: (tables) => invalidateTables(queryClient, tables),
  }),
  InstalledPlugins.load(new InstalledPluginsRepository(platform.prefs, platform.plugins), pagePluginLoader),
]);

const services = createAppServices(platform, database, theme, installedPlugins);
// Not awaited - the first render doesn't wait on the sign-in.
void services.sync.restoreConnection();

const root = document.getElementById('root');
if (root === null) throw new Error('No #root element');
createRoot(root).render(
  <StrictMode>
    <App services={services} queryClient={queryClient} />
  </StrictMode>,
);
