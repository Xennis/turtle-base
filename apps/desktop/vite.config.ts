import { defineConfig, type UserConfig } from 'vite-plus';

// The main process as ESM, the preload as CommonJS - a sandboxed preload
// can't be an ES module. Workspace packages are bundled in, Electron isn't,
// so the packaged app needs no node_modules.
const shared = {
  platform: 'node' as const,
  outDir: 'dist',
  deps: { neverBundle: ['electron'], alwaysBundle: [/^@turtle-base\//] },
  clean: false,
};

export default defineConfig({
  pack: [
    {
      ...shared,
      entry: { main: 'src/main.ts' },
      format: 'esm',
      // A "Desktop app" OAuth client isn't confidential (RFC 8252) - release builds carry it, see
      // packages/crdt-file-sync-google-drive/README.md.
      define: {
        bundledDriveClientId: JSON.stringify(process.env['DRIVE_DESKTOP_CLIENT_ID'] ?? ''),
        bundledDriveClientSecret: JSON.stringify(process.env['DRIVE_DESKTOP_CLIENT_SECRET'] ?? ''),
      },
    },
    { ...shared, entry: { preload: 'src/preload.ts' }, format: 'cjs' },
  ],
} satisfies UserConfig);
