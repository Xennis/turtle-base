import { defineConfig } from 'vite-plus';

export default defineConfig({
  test: {
    name: 'books-plugin',
    include: ['src/**/*.test.ts'],
  },
});
