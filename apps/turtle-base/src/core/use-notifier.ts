import { useSyncExternalStore } from 'react';

import type { Notifier } from './notifier.ts';

/** Re-renders when `notifier` notifies; `read` must return the same value for the same state (a snapshot). */
export function useNotifier<T>(notifier: Notifier, read: () => T): T {
  return useSyncExternalStore(notifier.subscribe, read);
}
