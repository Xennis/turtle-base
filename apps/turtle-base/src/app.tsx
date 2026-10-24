import { QueryClientProvider, type QueryClient } from '@tanstack/react-query';
import { useEffect } from 'react';
import { Toaster } from 'sonner';

import { AppScope, type AppServices } from './core/app-scope.tsx';
import { useAppliedTheme } from './core/theme/use-applied-theme.ts';
import { useIsDark } from './core/theme/use-is-dark.ts';
import { TooltipProvider } from './core/ui/tooltip.tsx';
import { AppShell } from './features/shell/widgets/app-shell.tsx';

/** The app's root, the same on every platform. */
export function App({ services, queryClient }: { services: AppServices; queryClient: QueryClient }) {
  useAppliedTheme(services.theme);
  const dark = useIsDark(services.theme);
  useEffect(() => {
    void services.platform.setSystemBarsDark(dark);
  }, [services.platform, dark]);
  return (
    <QueryClientProvider client={queryClient}>
      <AppScope services={services}>
        <TooltipProvider>
          <AppShell />
          <Toaster theme={dark ? 'dark' : 'light'} position="bottom-right" />
        </TooltipProvider>
      </AppScope>
    </QueryClientProvider>
  );
}
