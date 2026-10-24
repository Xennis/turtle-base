import { QueryClientProvider, type QueryClient } from '@tanstack/react-query';

import { AppScope, type AppServices } from './core/app-scope.tsx';
import { useAppliedTheme } from './core/theme/use-applied-theme.ts';
import { TooltipProvider } from './core/ui/tooltip.tsx';
import { AppShell } from './features/shell/widgets/app-shell.tsx';

/** The app's root, the same on every platform - the entry points only differ in how they get their Platform. */
export function App({ services, queryClient }: { services: AppServices; queryClient: QueryClient }) {
  useAppliedTheme(services.theme);
  return (
    <QueryClientProvider client={queryClient}>
      <AppScope services={services}>
        <TooltipProvider>
          <AppShell />
        </TooltipProvider>
      </AppScope>
    </QueryClientProvider>
  );
}
