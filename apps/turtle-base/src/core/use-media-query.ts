import { useSyncExternalStore } from 'react';

/** Whether `query` matches right now, e.g. a minimum window width - updates with it. */
export function useMediaQuery(query: string): boolean {
  return useSyncExternalStore(
    (onChange) => {
      const media = matchMedia(query);
      media.addEventListener('change', onChange);
      return () => media.removeEventListener('change', onChange);
    },
    () => matchMedia(query).matches,
  );
}
