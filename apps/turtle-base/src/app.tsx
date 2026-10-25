import { QueryClientProvider, type QueryClient } from '@tanstack/react-query';
import { Toaster } from 'sonner';

import { AppScope, type AppServices } from './core/app-scope.tsx';
import { useAppliedTheme } from './core/theme/use-applied-theme.ts';
import { useIsDark } from './core/theme/use-is-dark.ts';
import { useWindowChrome } from './core/theme/use-window-chrome.ts';
import { TooltipProvider } from './core/ui/tooltip.tsx';
import { AppShell } from './features/shell/widgets/app-shell.tsx';
import { WindowTitleBar } from './features/shell/widgets/window-title-bar.tsx';

/** The app's root, the same on every platform. */
export function App({ services, queryClient }: { services: AppServices; queryClient: QueryClient }) {
  useAppliedTheme(services.theme);
  const dark = useIsDark(services.theme);
  useWindowChrome(services.platform, services.theme, dark);
  return (
    <QueryClientProvider client={queryClient}>
      <AppScope services={services}>
        <TooltipProvider>
          <div className="flex h-full flex-col">
            {services.platform.kind === 'desktop' && <WindowTitleBar />}
            <div className="min-h-0 flex-1">
              <AppShell />
            </div>
          </div>
          <Toaster theme={dark ? 'dark' : 'light'} position="bottom-right" />
        </TooltipProvider>
      </AppScope>
    </QueryClientProvider>
  );
}
