import { resolve } from 'node:path';

import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { contentSecurityPolicy } from '@turtle-base/platform';
import { defineConfig, type Plugin } from 'vite-plus';

export default defineConfig({
  plugins: [react(), tailwindcss(), contentSecurityPolicyMeta()],
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

/** The content security policy as a meta tag in built pages - Capacitor sends no headers of its own. */
function contentSecurityPolicyMeta(): Plugin {
  return {
    name: 'turtle-base:content-security-policy',
    apply: 'build',
    transformIndexHtml: () => [
      {
        tag: 'meta',
        attrs: { 'http-equiv': 'Content-Security-Policy', content: contentSecurityPolicy },
        injectTo: 'head-prepend',
      },
    ],
  };
}
