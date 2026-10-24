import { createNodeSqlDriver } from '@turtle-base/platform/testing';

import { AppDatabase } from './app-database.ts';

/** A fresh in-memory database for tests, on Node's built-in SQLite. */
export function openTestDatabase(nodeId?: string): Promise<AppDatabase> {
  return AppDatabase.open({ sql: createNodeSqlDriver(), ...(nodeId === undefined ? {} : { nodeId }) });
}
