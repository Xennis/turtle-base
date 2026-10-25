import { defineConfig } from 'vite-plus';

export default defineConfig({
  test: {
    name: 'books',
    include: ['src/**/*.test.ts'],
  },
});
