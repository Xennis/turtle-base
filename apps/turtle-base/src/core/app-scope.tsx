import { booksPlugin } from '@turtle-base/books-plugin';
import type { Platform } from '@turtle-base/platform';
import { createContext, use, type ReactNode } from 'react';

import { AiKeyStorage } from '../features/ai/data/ai-key-storage.ts';
import { AiSettingsController } from '../features/ai/data/ai-settings-controller.ts';
import { AttachmentsRepository } from '../features/files/data/attachments-repository.ts';
import { PagesRepository } from '../features/pages/data/pages-repository.ts';
import { PluginInstancesRepository } from '../features/plugins/data/plugin-instances-repository.ts';
import { PluginRegistry } from '../features/plugins/data/plugin-registry.ts';
import { SpacesRepository } from '../features/spaces/data/spaces-repository.ts';
import { CollectionsRepository } from '../features/tables/data/collections-repository.ts';
import { FieldTypeRegistry } from '../features/tables/data/field-type-registry.ts';
import { FieldsRepository } from '../features/tables/data/fields-repository.ts';
import { FileStore } from '../packages/file-store/file-store.ts';
import { browserThumbnailMaker } from '../packages/file-store/thumbnails.ts';
import type { AppDatabase } from './database/app-database.ts';
import { AppSyncController } from './sync/app-sync-controller.ts';
import type { ThemeController } from './theme/theme-controller.ts';

/** App-wide services, provided once at the root. */
export interface AppServices {
  readonly platform: Platform;
  readonly database: AppDatabase;
  readonly theme: ThemeController;
  readonly plugins: PluginRegistry;
  readonly fieldTypes: FieldTypeRegistry;
  readonly files: FileStore;
  readonly spaces: SpacesRepository;
  readonly collections: CollectionsRepository;
  readonly fields: FieldsRepository;
  readonly pages: PagesRepository;
  readonly attachments: AttachmentsRepository;
  readonly pluginInstances: PluginInstancesRepository;
  readonly sync: AppSyncController;
  readonly aiSettings: AiSettingsController;
  readonly aiKeys: AiKeyStorage;
}

/** The plugins the app ships with - registered at build time. */
const shippedPlugins = new PluginRegistry([booksPlugin]);

export function createAppServices(platform: Platform, database: AppDatabase, theme: ThemeController): AppServices {
  const fieldTypes = new FieldTypeRegistry(shippedPlugins.variants);
  const files = new FileStore(platform.files, browserThumbnailMaker);
  const attachments = new AttachmentsRepository(database);
  return {
    platform,
    database,
    theme,
    plugins: shippedPlugins,
    fieldTypes,
    files,
    spaces: new SpacesRepository(database),
    collections: new CollectionsRepository(database),
    fields: new FieldsRepository(database, fieldTypes),
    pages: new PagesRepository(database),
    attachments,
    pluginInstances: new PluginInstancesRepository(database),
    sync: new AppSyncController({
      crdt: database.crdt,
      auth: platform.googleAuth,
      fetch: platform.fetch,
      files,
      attachments,
      prefs: platform.prefs,
      isMobile: platform.kind === 'android',
    }),
    aiSettings: new AiSettingsController(platform.prefs),
    aiKeys: new AiKeyStorage(platform.secrets),
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
