import type { Migration, MigrationProvider } from 'kysely/migration';

import { initial } from './0001-initial.ts';

/**
 * All migrations, by name - run in name order. Listed statically rather than
 * read from a folder, which a bundled app doesn't have.
 */
const migrations: Readonly<Record<string, Migration>> = {
  '0001-initial': initial,
};

export const migrationProvider: MigrationProvider = {
  getMigrations: () => Promise.resolve(migrations),
};
