import { createContext, use, type ReactNode } from 'react';

import { PagesRepository } from '../features/pages/data/pages-repository.ts';
import { SpacesRepository } from '../features/spaces/data/spaces-repository.ts';
import { CollectionsRepository } from '../features/tables/data/collections-repository.ts';
import type { AppDatabase } from './database/app-database.ts';
import type { ThemeController } from './theme/theme-controller.ts';

/** App-wide services, provided once at the root - like the Flutter app's AppScope. */
export interface AppServices {
  readonly database: AppDatabase;
  readonly theme: ThemeController;
  readonly spaces: SpacesRepository;
  readonly collections: CollectionsRepository;
  readonly pages: PagesRepository;
}

export function createAppServices(database: AppDatabase, theme: ThemeController): AppServices {
  return {
    database,
    theme,
    spaces: new SpacesRepository(database),
    collections: new CollectionsRepository(database),
    pages: new PagesRepository(database),
  };
}

const AppScopeContext = createContext<AppServices | undefined>(undefined);

export function AppScope({ services, children }: { services: AppServices; children: ReactNode }) {
  return <AppScopeContext value={services}>{children}</AppScopeContext>;
}

export function useAppServices(): AppServices {
  const services = use(AppScopeContext);
  if (services === undefined) throw new Error('useAppServices() outside of AppScope');
  return services;
}
