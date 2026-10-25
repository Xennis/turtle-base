import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

import { _electron as electron, type ElectronApplication, type Page } from 'playwright';

// Starts the built shell with the built renderer on a fresh profile and walks
// through the app shell: a space from the empty state, a collection and a
// page from the sidebar, the theme from Settings - and all of it again after
// a restart, so it came from SQLite and the prefs. Needs a display; run after
// `vp pack` here and `vp build` in apps/turtle-base. An optional argument is a
// folder to put screenshots in.

const appDir = join(import.meta.dirname, '..');
const userData = mkdtempSync(join(tmpdir(), 'turtle-base-smoke-'));
const screenshots = process.argv[2];

/** A 16×16 red PNG, the file picked whenever the app asks for one (see pickFilesFrom). */
const picture = join(userData, 'red.png');
writeFileSync(
  picture,
  Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAFklEQVR4nGO4o6ZGEmIY1TCqYfhqAAATqigQ9JeO5gAAAABJRU5ErkJggg==',
    'base64',
  ),
);

/**
 * A Flutter app's data folder for the import: a space with a page holding a heading and the picture. Its
 * tables as the Flutter app created them (drift's columns plus sql_crdt's), only those the import reads.
 */
const flutterData = join(userData, 'flutter');
const seedCount = 1500;
{
  const hash = `sha256-${createHash('sha256').update(readFileSync(picture)).digest('hex')}`;
  mkdirSync(join(flutterData, 'files'), { recursive: true });
  writeFileSync(join(flutterData, 'files', hash), readFileSync(picture));
  const audit = 'created_at INTEGER, updated_at INTEGER, created_by TEXT, updated_by TEXT, deleted_at INTEGER';
  const crdt = 'is_deleted INTEGER DEFAULT 0, hlc TEXT, node_id TEXT, modified TEXT';
  const row = "1784321678, 1784321678, 'flutter-user', 'flutter-user', NULL";
  const stamp = "0, 'hlc', 'flutter-node', 'hlc'";
  const database = new DatabaseSync(join(flutterData, 'turtle_base.sqlite'));
  database.exec(`
    CREATE TABLE users(id TEXT, name TEXT, created_at INTEGER, ${crdt});
    CREATE TABLE spaces(${audit}, id TEXT, name TEXT, icon TEXT, position INTEGER, ${crdt});
    CREATE TABLE collections(${audit}, id TEXT, space_id TEXT, name TEXT, icon TEXT, title_field_label TEXT, ${crdt});
    CREATE TABLE fields(${audit}, id TEXT, collection_id TEXT, name TEXT, type TEXT, position INTEGER, config TEXT, ${crdt});
    CREATE TABLE pages(${audit}, id TEXT, space_id TEXT, collection_id TEXT, parent_page_id TEXT, title TEXT, icon TEXT, properties TEXT, position INTEGER, ${crdt});
    CREATE TABLE blocks(${audit}, id TEXT, page_id TEXT, parent_block_id TEXT, type TEXT, position INTEGER, content TEXT, ${crdt});
    CREATE TABLE attachments(${audit}, id TEXT, page_id TEXT, field_id TEXT, file_hash TEXT, name TEXT, mime_type TEXT, size INTEGER, width INTEGER, height INTEGER, position INTEGER, ${crdt});
    INSERT INTO spaces VALUES (${row}, 'garden', 'Garden', NULL, 0, ${stamp});
    INSERT INTO pages VALUES (${row}, 'tomatoes', 'garden', NULL, NULL, 'Tomatoes', NULL, '{}', 0, ${stamp});
    INSERT INTO blocks VALUES (${row}, 'b1', 'tomatoes', NULL, 'heading', 0, '{"delta":[{"insert":"Planting"}],"level":2}', ${stamp});
    INSERT INTO blocks VALUES (${row}, 'b2', 'tomatoes', NULL, 'attachment', 1, '{"attachmentId":"a1"}', ${stamp});
    INSERT INTO attachments VALUES (${row}, 'a1', 'tomatoes', NULL, '${hash}', 'seedling.png', 'image/png', 79, 16, 16, 0, ${stamp});
    INSERT INTO collections VALUES (${row}, 'seeds', 'garden', 'Seeds', NULL, NULL, ${stamp});
  `);
  // Enough entries that only a part of them can be rendered at once.
  const entry = database.prepare(
    `INSERT INTO pages VALUES (${row}, ?, 'garden', 'seeds', NULL, ?, NULL, '{}', ?, ${stamp})`,
  );
  for (let i = 1; i <= seedCount; i++) entry.run(`seed-${i}`, `Seed ${String(i).padStart(4, '0')}`, i);
  database.close();
}

/** The file dialog is native - Playwright can't click it, so the main process gets one that picks `path`. */
async function pickFilesFrom(app: ElectronApplication, path: string) {
  await app.evaluate(({ dialog }, filePath) => {
    dialog.showOpenDialog = () => Promise.resolve({ canceled: false, filePaths: [filePath] });
  }, path);
}

/** The window last launched - screenshotted when a step fails. */
let current: Page | undefined;

async function launch() {
  const app = await electron.launch({
    // No OS keyring for the secrets - there may be none where this runs (see below).
    args: [appDir, `--user-data-dir=${userData}`, '--password-store=basic'],
    // An OAuth client, so Drive sync is offered - Google itself is answered by answerRequests.
    env: {
      ...process.env,
      DRIVE_DESKTOP_CLIENT_ID: 'smoke-client',
      DRIVE_DESKTOP_CLIENT_SECRET: 'smoke-secret',
      TURTLE_FLUTTER_DATA_DIR: flutterData,
    },
  });
  await pickFilesFrom(app, picture);
  await answerRequests(app);
  // Secrets stored with Chromium's built-in key - the app itself refuses that without being told to.
  await app.evaluate(({ safeStorage }) => safeStorage.setUsePlainTextEncryption(true));
  const page = await app.firstWindow();
  current = page;
  page.on('pageerror', (error) => console.log(`[renderer error] ${error.message}`));
  page.on('console', (message) => {
    if (message.type() === 'error' || message.type() === 'warning')
      console.log(`[renderer ${message.type()}] ${message.text()}`);
  });
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
  await addField(page, 'Photo', 'Files');
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

  await editEntry(page);
}

/** The entry's page: its field values above, text in the block editor - stored, so it's there when reopened. */
async function editEntry(page: Page) {
  await page.locator('tbody').getByRole('button', { name: 'Open' }).click();
  await page.locator('input[aria-label="Title"][value="Squats"]').waitFor();
  await page.getByRole('term').filter({ hasText: 'Reps' }).waitFor();
  await page.getByRole('button', { name: 'Icon' }).click();
  await page.getByRole('button', { name: 'Grinning Face', exact: true }).waitFor();
  await screenshot(page, '2d-emoji-picker');
  await page.getByRole('textbox', { name: 'Search emoji' }).fill('biceps');
  await page.getByRole('button', { name: 'Flexed Biceps' }).click();
  await page.getByRole('button', { name: 'Icon' }).filter({ hasText: '💪' }).waitFor();
  await page.getByRole('button', { name: 'Add file' }).click();
  await page.getByRole('button', { name: 'Open red.png' }).locator('img').waitFor();
  await page.locator('.bn-editor').click();
  await page.keyboard.type('Three sets, slow on the way down.');
  await page.getByRole('button', { name: 'Attach file' }).click();
  await page.locator('.bn-editor').getByRole('button', { name: 'Open red.png' }).waitFor();
  // Written after a short pause in typing.
  await page.waitForTimeout(1000);
  await screenshot(page, '2d-page');

  await page.getByRole('button', { name: 'Back to collection' }).click();
  await page.locator('tbody').getByRole('button', { name: 'Open' }).click();
  await page.locator('.bn-editor').getByText('Three sets, slow on the way down.').waitFor();
  await page.getByRole('button', { name: 'Icon' }).filter({ hasText: '💪' }).waitFor();
  await page.locator('.bn-editor').getByRole('button', { name: 'Open red.png' }).waitFor();
  await page.getByRole('button', { name: 'Back to collection' }).click();
}

/**
 * Requests go out through the main process (Platform.fetch); answering them there keeps the test off the
 * network: Open Library's search finds "Dune" and every cover is the test PNG, Anthropic answers the test
 * prompt, and Google's token endpoint hands out tokens. The browser for Google's consent page agrees right
 * away, following the redirect back.
 */
async function answerRequests(app: ElectronApplication) {
  await app.evaluate(({ net, shell }, png) => {
    // The app's own files come through net.fetch too - those still load.
    const original = net.fetch.bind(net);
    net.fetch = (input: string | Request, init?: RequestInit) => {
      const url = new URL(typeof input === 'string' ? input : input.url);
      if (url.hostname === 'covers.openlibrary.org') {
        return Promise.resolve(new Response(Buffer.from(png, 'base64'), { headers: { 'Content-Type': 'image/png' } }));
      }
      if (url.hostname === 'openlibrary.org') {
        const dune = {
          key: '/works/OL893415W',
          title: 'Dune',
          author_name: ['Frank Herbert'],
          first_publish_year: 1965,
          cover_i: 1,
          editions: { docs: [{ title: 'Dune', cover_i: 1 }] },
        };
        return Promise.resolve(Response.json({ docs: [dune] }));
      }
      if (url.hostname === 'api.anthropic.com') {
        const headers = new Headers(typeof input === 'string' ? init?.headers : input.headers);
        if (headers.get('x-api-key') !== 'sk-smoke') return Promise.resolve(new Response(null, { status: 401 }));
        return Promise.resolve(
          Response.json({
            id: 'msg_smoke',
            type: 'message',
            role: 'assistant',
            model: 'claude-sonnet-5-5',
            content: [{ type: 'text', text: 'All good here.' }],
            stop_reason: 'end_turn',
            stop_sequence: null,
            usage: { input_tokens: 3, output_tokens: 4 },
          }),
        );
      }
      if (url.hostname === 'oauth2.googleapis.com') {
        return Promise.resolve(Response.json({ access_token: 'access', expires_in: 3600, refresh_token: 'refresh' }));
      }
      return original(input, init);
    };
    const openExternal = shell.openExternal.bind(shell);
    shell.openExternal = async (url: string) => {
      const consent = new URL(url);
      if (consent.hostname !== 'accounts.google.com') return openExternal(url);
      const redirect = new URL(consent.searchParams.get('redirect_uri') ?? '');
      redirect.search = new URLSearchParams({
        code: 'code',
        state: consent.searchParams.get('state') ?? '',
      }).toString();
      await fetch(redirect);
    };
  }, readFileSync(picture).toString('base64'));
}

/** A big collection renders only what's in view - in the table and the tiles - and scrolls to its end. */
async function scrollThroughSeeds(page: Page) {
  await page.getByRole('button', { name: 'Seeds' }).click();
  await page.getByText(`${seedCount} entries`).waitFor();
  const last = `Seed ${String(seedCount).padStart(4, '0')}`;
  for (const layout of ['Table', 'Tiles']) {
    await page.getByRole('radio', { name: layout }).click();
    await page.getByText('Seed 0001').waitFor();
    await screenshot(page, `8-seeds-${layout.toLowerCase()}`);
    const rendered = await page.getByText(/^Seed \d{4}$/).count();
    if (rendered > 200) throw new Error(`${layout}: ${rendered} of ${seedCount} entries rendered`);
    await page.getByText('Seed 0001').hover();
    for (let i = 0; i < 200 && !(await page.getByText(last).isVisible()); i++) await page.mouse.wheel(0, 4000);
    await page.getByText(last).waitFor();
    await page.mouse.wheel(0, -10_000_000);
  }
  await page.getByRole('radio', { name: 'Table' }).click();
}

/** The Books plugin: added as a space, a book looked up, added - and opened, not added again, the second time. */
async function addBook(page: Page) {
  await page.getByRole('button', { name: 'Plugins' }).click();
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  await page.getByRole('button', { name: 'Reading list' }).click();
  for (const time of ['first', 'second']) {
    await page.getByRole('button', { name: 'Add book' }).click();
    await page.getByRole('textbox', { name: 'Search' }).fill('dune');
    await page.getByRole('button', { name: /^Dune/ }).click();
    await page.locator('input[aria-label="Title"][value="Dune"]').waitFor();
    await page.getByText('Frank Herbert').waitFor();
    if (time === 'first') {
      // The cover is downloaded after the entry is there.
      await page.getByRole('button', { name: 'Open 1-L.jpg' }).locator('img').waitFor();
      await screenshot(page, '6-book');
    }
    await page.getByRole('button', { name: 'Back to collection' }).click();
  }
  await page.getByText('1 entry').waitFor();
}

try {
  const first = await launch();
  await first.page.getByText('No spaces yet').waitFor();
  // The page draws the title bar; the system's window buttons lie over it.
  // Not in TypeScript's DOM types yet.
  const overlay = await first.page.evaluate(
    () => Reflect.get(Reflect.get(navigator, 'windowControlsOverlay') ?? {}, 'visible') === true,
  );
  if (!overlay) {
    throw new Error('The window has a system title bar');
  }
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
  await first.page.getByLabel('Anthropic (Claude)').fill('sk-smoke');
  await first.page.getByLabel('Anthropic (Claude)').press('Enter');
  await first.page.getByText('Key saved').waitFor();
  await first.page.getByRole('combobox', { name: 'Default model' }).click();
  await first.page.getByRole('option', { name: 'Claude Sonnet 5.5' }).click();
  await first.page.getByRole('button', { name: 'Send test prompt' }).click();
  await first.page.getByText('All good here.').waitFor();
  await first.page.getByRole('status').filter({ hasText: 'Not connected' }).waitFor();
  await first.page.getByRole('button', { name: 'Connect' }).click();
  await first.page
    .getByRole('status')
    .filter({ hasText: /^Connected$/ })
    .waitFor();
  await first.page.getByRole('button', { name: 'Import from the Flutter app' }).click();
  // No file counted: the picture is the one attached earlier - already in the store, stored once.
  await first.page.getByText(`Imported 1 space, 1 collection, ${seedCount + 1} pages.`).waitFor();
  await screenshot(first.page, '3-settings-dark');
  await first.app.close();

  const second = await launch();
  await second.page.getByRole('combobox', { name: 'Space' }).filter({ hasText: 'Fitness' }).waitFor();
  await second.page.getByRole('button', { name: 'Workouts' }).click();
  await second.page.locator('html.dark[data-preset="violet"]').waitFor({ state: 'attached' });
  await screenshot(second.page, '4-restarted');
  // Still connected after the restart - the refresh token was kept.
  await second.page.getByRole('button', { name: 'Settings' }).click();
  await second.page
    .getByRole('status')
    .filter({ hasText: /^Connected$/ })
    .waitFor();
  await second.page.getByRole('button', { name: 'Disconnect' }).click();
  await second.page.getByRole('status').filter({ hasText: 'Not connected' }).waitFor();
  await addBook(second.page);
  // The Flutter app's page, imported before the restart: its text in BlockNote, its picture in the store.
  await second.page.getByRole('combobox', { name: 'Space' }).click();
  await second.page.getByRole('option', { name: 'Garden' }).click();
  await second.page.getByRole('button', { name: 'Tomatoes' }).click();
  await second.page.locator('.bn-editor').getByRole('heading', { name: 'Planting' }).waitFor();
  await second.page.locator('.bn-editor').getByRole('button', { name: 'Open seedling.png' }).locator('img').waitFor();
  await screenshot(second.page, '7-imported');
  await scrollThroughSeeds(second.page);
  await second.page.getByRole('combobox', { name: 'Space' }).click();
  await second.page.getByRole('option', { name: 'Fitness' }).click();
  await second.page.getByRole('button', { name: 'Workouts' }).click();

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
