import { defineConfig } from 'vite-plus';

export default defineConfig({
  test: {
    name: 'app',
    include: ['src/**/*.test.ts'],
  },
});
