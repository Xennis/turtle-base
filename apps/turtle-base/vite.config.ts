import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite-plus';

export default defineConfig({
  plugins: [react()],
  build: {
    // Top-level await in the entry - every target web view supports it.
    target: 'es2024',
  },
  test: {
    name: 'app',
    include: ['src/**/*.test.ts'],
  },
});
