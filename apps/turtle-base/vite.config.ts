import { resolve } from 'node:path';

import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite-plus';

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    // Only for the shadcn/ui components in src/core/ui, which import each other this way.
    alias: { '@': resolve(import.meta.dirname, 'src') },
  },
  build: {
    // Top-level await in the entry - every target web view supports it.
    target: 'es2024',
  },
  test: {
    name: 'app',
    include: ['src/**/*.test.ts'],
  },
});
