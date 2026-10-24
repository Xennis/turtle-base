import { useQuery, type QueryClient, type UseQueryResult } from '@tanstack/react-query';

import type { Database } from './schema.ts';

declare module '@tanstack/react-query' {
  interface Register {
    queryMeta: { tables?: readonly (keyof Database)[] };
  }
}

/**
 * A query on the database that refreshes whenever one of `tables` changes -
 * through a local write or a merge from sync (see {@link invalidateTables}).
 * Replaces the Flutter app's drift streams.
 */
export function useDbQuery<T>(options: {
  tables: readonly (keyof Database)[];
  key: readonly unknown[];
  query: () => Promise<T>;
}): UseQueryResult<T> {
  return useQuery({
    queryKey: [...options.tables, ...options.key],
    queryFn: options.query,
    meta: { tables: options.tables },
    staleTime: Infinity,
  });
}

/** Refreshes the queries of {@link useDbQuery} that read one of `tables` - hand it to `AppDatabase.open`. */
export function invalidateTables(client: QueryClient, tables: readonly string[]): void {
  void client.invalidateQueries({
    predicate: (query) => query.meta?.tables?.some((table) => tables.includes(table)) ?? false,
  });
}
