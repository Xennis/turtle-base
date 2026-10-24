import { createContext, use, type ReactNode } from 'react';

import type { AppDatabase } from './database/app-database.ts';

/** App-wide services, provided once at the root - like the Flutter app's AppScope. */
export interface AppServices {
  readonly database: AppDatabase;
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
