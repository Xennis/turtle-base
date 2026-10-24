import { defineConfig } from 'vite-plus';

export default defineConfig({
  test: {
    name: 'platform',
    include: ['src/**/*.test.ts'],
  },
});
