import { defineConfig, type UserConfig } from 'vite-plus';

// The main process as ESM, the preload as CommonJS - a sandboxed preload
// can't be an ES module. Workspace packages are bundled in, Electron isn't.
const shared = {
  platform: 'node' as const,
  outDir: 'dist',
  deps: { neverBundle: ['electron'], alwaysBundle: [/^@turtle-base\//] },
  clean: false,
};

export default defineConfig({
  pack: [
    { ...shared, entry: { main: 'src/main.ts' }, format: 'esm' },
    { ...shared, entry: { preload: 'src/preload.ts' }, format: 'cjs' },
  ],
} satisfies UserConfig);
