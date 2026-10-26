/**
 * The window's title bar on macOS, drawn by the page in the theme's colors -
 * the traffic lights sit on top of it, clear of the centered title. Dragging
 * it moves the window.
 */
export function WindowTitleBar() {
  return (
    <div
      data-tauri-drag-region
      className="flex h-9 shrink-0 items-center justify-center text-xs text-muted-foreground select-none"
    >
      turtle-base
    </div>
  );
}
