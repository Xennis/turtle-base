import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { _electron as electron, type Page } from 'playwright';

// Starts the built shell with the built renderer on a fresh profile and walks
// through the app shell: a space from the empty state, a collection and a
// page from the sidebar, the theme from Settings - and all of it again after
// a restart, so it came from SQLite and the prefs. Needs a display; run after
// `vp pack` here and `vp build` in apps/turtle-base. An optional argument is a
// folder to put screenshots in.

const appDir = join(import.meta.dirname, '..');
const userData = mkdtempSync(join(tmpdir(), 'turtle-base-smoke-'));
const screenshots = process.argv[2];

async function launch() {
  const app = await electron.launch({ args: [appDir, `--user-data-dir=${userData}`] });
  const page = await app.firstWindow();
  page.on('pageerror', (error) => console.log(`[renderer error] ${error.message}`));
  return { app, page };
}

async function screenshot(page: Page, name: string) {
  if (screenshots !== undefined)
    await page.screenshot({ path: join(screenshots, `${name}.png`), animations: 'disabled' });
}

async function createNamed(page: Page, button: string, name: string) {
  await page.getByRole('button', { name: button }).click();
  await page.getByRole('textbox', { name: 'Name', exact: true }).fill(name);
  await page.getByRole('button', { name: 'Create' }).click();
}

try {
  const first = await launch();
  await first.page.getByText('No spaces yet').waitFor();
  await screenshot(first.page, '1-empty');
  await createNamed(first.page, 'Create your first space', 'Fitness');
  await first.page.getByRole('combobox', { name: 'Space' }).filter({ hasText: 'Fitness' }).waitFor();

  await createNamed(first.page, 'New collection', 'Workouts');
  await first.page.getByRole('button', { name: 'Workouts' }).waitFor();
  await first.page.getByText('No entries yet').waitFor();
  await first.page.getByRole('button', { name: 'New page' }).click();
  await first.page.getByRole('button', { name: 'Untitled' }).waitFor();
  await screenshot(first.page, '2-shell');

  await first.page.getByRole('button', { name: 'Settings' }).click();
  await first.page.getByRole('radio', { name: 'Dark' }).click();
  await first.page.getByRole('radio', { name: 'Violet' }).click();
  await first.page.locator('html.dark[data-preset="violet"]').waitFor({ state: 'attached' });
  await screenshot(first.page, '3-settings-dark');
  await first.app.close();

  const second = await launch();
  await second.page.getByRole('combobox', { name: 'Space' }).filter({ hasText: 'Fitness' }).waitFor();
  await second.page.getByRole('button', { name: 'Workouts' }).click();
  await second.page.locator('html.dark[data-preset="violet"]').waitFor({ state: 'attached' });
  await screenshot(second.page, '4-restarted');

  await second.app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0]?.setSize(400, 760));
  await second.page.getByRole('button', { name: 'Back' }).click();
  await second.page.getByRole('button', { name: 'Open sidebar' }).click();
  await second.page.getByRole('dialog').getByRole('button', { name: 'Workouts' }).waitFor();
  await screenshot(second.page, '5-narrow-drawer');
  await second.app.close();
  console.log('Smoke test passed');
} finally {
  rmSync(userData, { recursive: true, force: true });
}
