import { defineConfig } from 'vite-plus';

export default defineConfig({
  test: {
    name: 'sql-crdt',
    include: ['src/**/*.test.ts'],
  },
});
