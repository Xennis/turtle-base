import { defineConfig } from 'vite-plus';

export default defineConfig({
  test: {
    name: 'field-types',
    include: ['src/**/*.test.ts'],
  },
});
