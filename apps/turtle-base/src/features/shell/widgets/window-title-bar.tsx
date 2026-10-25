/**
 * The desktop window's title bar, drawn by the page in the theme's colors -
 * the system's window buttons sit on top of it. The Window Controls Overlay
 * variables keep it clear of them: on the right on Linux and Windows, of the
 * traffic lights on the left on macOS.
 */
export function WindowTitleBar() {
  return (
    <div className="flex h-[env(titlebar-area-height,36px)] w-[env(titlebar-area-width,100%)] shrink-0 items-center justify-center pl-[env(titlebar-area-x,0px)] text-xs text-muted-foreground select-none [app-region:drag]">
      turtle-base
    </div>
  );
}
