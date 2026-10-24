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

/** The window last launched - screenshotted when a step fails. */
let current: Page | undefined;

async function launch() {
  const app = await electron.launch({ args: [appDir, `--user-data-dir=${userData}`] });
  const page = await app.firstWindow();
  current = page;
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

async function addField(page: Page, name: string, type: string) {
  await page.getByLabel('New field name').fill(name);
  await page.getByRole('combobox', { name: 'Field type' }).last().click();
  await page.getByRole('option', { name: type, exact: true }).click();
  await page.getByRole('button', { name: 'Add field' }).click();
  await page.locator(`input[aria-label="Field name"][value="${name}"]`).waitFor();
}

async function changeFieldType(page: Page, index: number, type: string) {
  await page.getByRole('combobox', { name: 'Field type' }).nth(index).click();
  await page.getByRole('option', { name: type, exact: true }).click();
}

/** Fields, values, the option picker, tiles and type changes of the open, empty collection. */
async function editCollection(page: Page) {
  await page.getByRole('button', { name: 'Edit collection' }).click();
  await addField(page, 'Reps', 'Number');
  await addField(page, 'Status', 'Select');
  // A new select's settings open right away, to add its options.
  await page.getByLabel('New option').fill('Done');
  await page.getByLabel('New option').press('Enter');
  await page.locator('input[aria-label="Option name"][value="Done"]').waitFor();
  await screenshot(page, '2a-edit-page');
  await page.getByRole('button', { name: 'Back' }).click();

  await page.getByRole('button', { name: 'New entry' }).click();
  const body = page.locator('tbody');
  await body.getByRole('button', { name: /^Name:/ }).click();
  await page.getByRole('textbox', { name: 'Name', exact: true }).fill('Squats');
  await page.getByRole('textbox', { name: 'Name', exact: true }).press('Enter');
  await body.getByText('Squats').waitFor();

  await body.getByRole('button', { name: /^Reps:/ }).click();
  const reps = page.getByRole('textbox', { name: 'Reps', exact: true });
  await reps.fill('a dozen');
  await reps.press('Enter');
  // Not a number: the input stays, flagged, and nothing is saved.
  await page.locator('input[aria-label="Reps"][aria-invalid="true"]').waitFor();
  await reps.fill('12');
  await reps.press('Enter');
  await body.getByText('12', { exact: true }).waitFor();

  await body.getByRole('button', { name: /^Status:/ }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Done' }).click();
  await body.getByText('Done').waitFor();
  await screenshot(page, '2b-table');

  await page.getByRole('radio', { name: 'Tiles' }).click();
  await page.getByRole('button', { name: 'Squats' }).waitFor();
  await screenshot(page, '2c-tiles');
  await page.getByRole('radio', { name: 'Table' }).click();

  // Number to text keeps the values as they are; select to text rewrites option ids as names - after asking.
  await page.getByRole('button', { name: 'Edit collection' }).click();
  await changeFieldType(page, 0, 'Text');
  await changeFieldType(page, 1, 'Text');
  await page.getByRole('alertdialog').getByRole('button', { name: 'Change type' }).click();
  await page.getByRole('combobox', { name: 'Field type' }).nth(1).filter({ hasText: 'Text' }).waitFor();
  await page.getByRole('button', { name: 'Back' }).click();
  await body.getByText('Done').waitFor();
  await body.getByText('12', { exact: true }).waitFor();
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
  await editCollection(first.page);
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
} catch (error) {
  if (current !== undefined) await screenshot(current, 'failure').catch(() => undefined);
  throw error;
} finally {
  rmSync(userData, { recursive: true, force: true });
}
