/**
 * The desktop window's title bar, drawn by the page in the theme's colors -
 * the system's window buttons sit on top of it. Electron's Window Controls
 * Overlay variables keep it clear of them; in Tauri on macOS the title stays
 * centered, clear of the traffic lights. It moves the window in both
 * (`app-region` in Electron, `data-tauri-drag-region` in Tauri).
 */
export function WindowTitleBar() {
  return (
    <div
      data-tauri-drag-region
      className="flex h-[env(titlebar-area-height,36px)] w-[env(titlebar-area-width,100%)] shrink-0 items-center justify-center pl-[env(titlebar-area-x,0px)] text-xs text-muted-foreground select-none [app-region:drag]"
    >
      turtle-base
    </div>
  );
}
