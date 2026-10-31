import { defineConfig } from 'vite-plus';

export default defineConfig({
  test: {
    name: 'plugin-catalog',
    include: ['src/**/*.test.ts'],
  },
});
