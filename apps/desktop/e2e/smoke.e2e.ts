import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { _electron as electron } from 'playwright';

// Starts the built shell with the built renderer on a fresh profile, adds a
// space and checks it's listed - after a restart too, so it came from SQLite.
// Needs a display; run after `vp pack` here and `vp build` in apps/turtle-base.

const appDir = join(import.meta.dirname, '..');
const userData = mkdtempSync(join(tmpdir(), 'turtle-base-smoke-'));
const screenshot = process.argv[2];

async function launch() {
  const app = await electron.launch({ args: [appDir, `--user-data-dir=${userData}`] });
  const page = await app.firstWindow();
  page.on('console', (message) => console.log(`[renderer] ${message.text()}`));
  page.on('pageerror', (error) => console.log(`[renderer error] ${error.message}`));
  return { app, page };
}

try {
  const first = await launch();
  await first.page.getByText('No spaces yet').waitFor();
  await first.page.getByLabel('Space name').fill('Fitness');
  await first.page.getByRole('button', { name: 'Add space' }).click();
  await first.page.getByRole('listitem').filter({ hasText: 'Fitness' }).waitFor();
  await first.app.close();

  const second = await launch();
  await second.page.getByRole('listitem').filter({ hasText: 'Fitness' }).waitFor();
  if (screenshot !== undefined) await second.page.screenshot({ path: screenshot });
  await second.app.close();
  console.log('Smoke test passed');
} finally {
  rmSync(userData, { recursive: true, force: true });
}
