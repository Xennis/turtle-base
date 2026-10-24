import { defineConfig } from 'vite-plus';

export default defineConfig({
  test: {
    name: 'crdt-file-sync-google-drive',
    include: ['src/**/*.test.ts'],
  },
});
