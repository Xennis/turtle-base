import { resolve } from 'node:path';

import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { contentSecurityPolicy } from '@turtle-base/platform';
import { defineConfig, type Plugin } from 'vite-plus';

/** The smoke test's build, see src/core/platform/e2e-hooks.ts. */
const e2eBuild = process.env['TURTLE_E2E'] === '1';

export default defineConfig({
  plugins: [react(), tailwindcss(), contentSecurityPolicyMeta()],
  // A "Desktop app" OAuth client isn't confidential (RFC 8252) - release builds carry it, see
  // packages/crdt-file-sync-google-drive/README.md.
  define: {
    bundledDriveClientId: JSON.stringify(process.env['DRIVE_DESKTOP_CLIENT_ID'] ?? ''),
    bundledDriveClientSecret: JSON.stringify(process.env['DRIVE_DESKTOP_CLIENT_SECRET'] ?? ''),
    e2eBuild: JSON.stringify(e2eBuild),
  },
  server: {
    // `tauri android dev` loads the page from this machine's address on the network.
    host: process.env['TAURI_DEV_HOST'] ?? false,
  },
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

/** The content security policy as a meta tag in built pages - Tauri's own (tauri.conf.json) is off, so this is the one. */
function contentSecurityPolicyMeta(): Plugin {
  return {
    name: 'turtle-base:content-security-policy',
    apply: 'build',
    transformIndexHtml: () => [
      {
        tag: 'meta',
        attrs: {
          'http-equiv': 'Content-Security-Policy',
          // The smoke test follows the sign-in's redirect to the shell's loopback server from the page.
          content: e2eBuild
            ? contentSecurityPolicy.replace("connect-src 'self'", "connect-src 'self' http://127.0.0.1:*")
            : contentSecurityPolicy,
        },
        injectTo: 'head-prepend',
      },
    ],
  };
}
