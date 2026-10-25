import { type ChildProcess, spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

import { remote } from 'webdriverio';

// Starts the shell's debug build - built with TURTLE_E2E=1, see the
// desktop-smoke task - on a fresh profile and walks through the app shell: a
// space from the empty state, a collection and a page from the sidebar, the
// theme from Settings - and all of it again after a restart, so it came from
// SQLite and the prefs. Linux only (tauri-driver drives WebKitGTK through
// WebKitWebDriver), needs a display. TURTLE_SMOKE_EXECUTABLE runs another
// binary; an optional argument is a folder to put screenshots in.

const home = mkdtempSync(join(tmpdir(), 'turtle-base-smoke-'));
const screenshots = process.argv[2];
const application =
  process.env['TURTLE_SMOKE_EXECUTABLE'] ?? join(import.meta.dirname, '../src-tauri/target/debug/turtle-base');

/** A 16×16 red PNG, the file picked whenever the app asks for one. */
const picture = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAFklEQVR4nGO4o6ZGEmIY1TCqYfhqAAATqigQ9JeO5gAAAABJRU5ErkJggg==',
  'base64',
);

/**
 * A Flutter app's data folder for the import: a space with a page holding a heading and the picture. Its
 * tables as the Flutter app created them (drift's columns plus sql_crdt's), only those the import reads.
 */
const flutterData = join(home, 'flutter');
const seedCount = 1500;
{
  const hash = `sha256-${createHash('sha256').update(picture).digest('hex')}`;
  mkdirSync(join(flutterData, 'files'), { recursive: true });
  writeFileSync(join(flutterData, 'files', hash), picture);
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

type Browser = WebdriverIO.Browser;

declare global {
  namespace WebdriverIO {
    interface Capabilities {
      /** tauri-driver's: the app to start. */
      'tauri:options'?: { application: string };
    }
  }
}

/** A pattern as it crosses into the page - RegExps can't, their source and flags can. */
type Pattern = string | { source: string; flags: string } | null;

interface Query {
  /** The name exactly - else, like in Playwright, a case-insensitive substring of it. */
  readonly exact?: boolean;
  /** A CSS selector the element has to be inside of. */
  readonly within?: string;
  /** Only elements whose text contains this (a string) or matches it. */
  readonly hasText?: string | RegExp;
  /** Only elements with a descendant matching this CSS selector. */
  readonly has?: string;
  /** Which of the matches - the first by default, -1 for the last. */
  readonly nth?: number;
}

/** The window last launched - screenshotted when a step fails. */
let current: Browser | undefined;

/**
 * The visible element of `kind` (a role) whose accessible name matches `name` - a small stand-in for
 * Playwright's getByRole, which WebDriver doesn't have. Waits for it.
 */
async function role(browser: Browser, kind: string, name: string | RegExp | undefined, query: Query = {}) {
  return found(browser, `${kind} ${String(name ?? '')}`, () =>
    browser.execute(findByRole, kind, patternOf(name), {
      exact: query.exact ?? false,
      within: query.within ?? null,
      hasText: patternOf(query.hasText),
      has: query.has ?? null,
      nth: query.nth ?? 0,
    }),
  );
}

/** The innermost visible element containing `value` (a substring), like Playwright's getByText. */
async function text(browser: Browser, value: string | RegExp, within?: string) {
  return found(browser, `text ${String(value)}`, () => browser.execute(findByText, patternOf(value), within ?? null));
}

// Functions passed to execute() run in the page, on their own - their helpers have to be inside them.
/* oxlint-disable unicorn/consistent-function-scoping */

function findByRole(
  kind: string,
  pattern: Pattern,
  query: { exact: boolean; within: string | null; hasText: Pattern; has: string | null; nth: number },
): Element | null {
  const selectors: Record<string, string> = {
    button: 'button, [role="button"]',
    radio: '[role="radio"], input[type="radio"]',
    option: '[role="option"]',
    combobox: '[role="combobox"]',
    textbox: 'input:not([type="radio"]):not([type="checkbox"]), textarea, [role="textbox"]',
    status: '[role="status"]',
    heading: 'h1, h2, h3, h4, h5, h6, [role="heading"]',
    dialog: '[role="dialog"]',
    alertdialog: '[role="alertdialog"]',
    term: 'dt, [role="term"]',
  };
  const textOf = (element: Element | null) => (element?.textContent ?? '').replace(/\s+/g, ' ').trim();
  const nameOf = (element: Element) => {
    const label = element.getAttribute('aria-label');
    if (label !== null) return label.trim();
    const labelledBy = element.getAttribute('aria-labelledby');
    if (labelledBy !== null)
      return labelledBy
        .split(' ')
        .map((id) => textOf(document.getElementById(id)))
        .join(' ');
    if (element.id.length > 0) {
      const labelFor = document.querySelector(`label[for="${CSS.escape(element.id)}"]`);
      if (labelFor !== null) return textOf(labelFor);
    }
    return element.matches('input, textarea') ? (element.getAttribute('placeholder') ?? '') : textOf(element);
  };
  const matches = (value: string, expected: Pattern, exact: boolean) =>
    expected === null ||
    (typeof expected === 'string'
      ? exact
        ? value === expected
        : value.toLowerCase().includes(expected.toLowerCase())
      : new RegExp(expected.source, expected.flags).test(value));
  const roots = query.within === null ? [document] : [...document.querySelectorAll(query.within)];
  const candidates = roots
    .flatMap((root) => [...root.querySelectorAll(selectors[kind] ?? `[role="${kind}"]`)])
    // Like the accessibility tree: what a modal dialog hides (aria-hidden) isn't there.
    .filter(
      (element) => element.getClientRects().length > 0 && element.closest('[aria-hidden="true"], [inert]') === null,
    )
    .filter((element) => matches(nameOf(element), pattern, query.exact))
    .filter((element) => matches(textOf(element), query.hasText, false))
    .filter((element) => query.has === null || element.querySelector(query.has) !== null);
  return candidates.at(query.nth) ?? null;
}

function findByText(pattern: Pattern, within: string | null): Element | null {
  const roots = within === null ? [document.body] : [...document.querySelectorAll(within)];
  const textOf = (element: Element) => (element.textContent ?? '').replace(/\s+/g, ' ').trim();
  const contains = (element: Element) =>
    pattern === null ||
    (typeof pattern === 'string'
      ? textOf(element).includes(pattern)
      : new RegExp(pattern.source, pattern.flags).test(textOf(element)));
  for (const root of roots) {
    const all = [...root.querySelectorAll('*')].filter(
      (element) => element.getClientRects().length > 0 && contains(element),
    );
    const innermost = all.find((element) => ![...element.children].some((child) => contains(child)));
    if (innermost !== undefined) return innermost;
  }
  return null;
}

function installHooks(png: string) {
  const json = (value: unknown) => ({
    headers: { 'Content-Type': 'application/json' },
    base64: btoa(JSON.stringify(value)),
  });
  Reflect.set(window, 'turtleE2e', {
    pickFiles: [{ name: 'red.png', base64: png }],
    answer: ({ url, headers }: { url: string; headers: Record<string, string> }) => {
      const { hostname } = new URL(url);
      if (hostname === 'covers.openlibrary.org') return { headers: { 'Content-Type': 'image/png' }, base64: png };
      if (hostname === 'openlibrary.org') {
        const dune = {
          key: '/works/OL893415W',
          title: 'Dune',
          author_name: ['Frank Herbert'],
          first_publish_year: 1965,
          cover_i: 1,
          editions: { docs: [{ title: 'Dune', cover_i: 1 }] },
        };
        return json({ docs: [dune] });
      }
      if (hostname === 'api.anthropic.com') {
        if (headers['x-api-key'] !== 'sk-smoke') return { status: 401 };
        return json({
          id: 'msg_smoke',
          type: 'message',
          role: 'assistant',
          model: 'claude-sonnet-5-5',
          content: [{ type: 'text', text: 'All good here.' }],
          stop_reason: 'end_turn',
          stop_sequence: null,
          usage: { input_tokens: 3, output_tokens: 4 },
        });
      }
      if (hostname === 'oauth2.googleapis.com') {
        return json({ access_token: 'access', expires_in: 3600, refresh_token: 'refresh' });
      }
      return undefined;
    },
    openExternal: async (url: string) => {
      const consent = new URL(url);
      if (consent.hostname !== 'accounts.google.com') return false;
      const redirect = new URL(consent.searchParams.get('redirect_uri') ?? '');
      redirect.search = new URLSearchParams({
        code: 'code',
        state: consent.searchParams.get('state') ?? '',
      }).toString();
      // The loopback server sends no CORS headers - the request is what counts, not its answer.
      await fetch(redirect, { mode: 'no-cors' });
      return true;
    },
  });
}

/* oxlint-enable unicorn/consistent-function-scoping */

/** Polls `find` until it returns an element. */
async function found(browser: Browser, description: string, find: () => Promise<unknown>) {
  let reference: unknown = null;
  await browser.waitUntil(
    async () => {
      reference = await find();
      return reference !== null;
    },
    { timeout: 15_000, interval: 100, timeoutMsg: `Not found: ${description}` },
  );
  // An element reference from execute(), which $() takes as it is.
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion
  return browser.$(reference as WebdriverIO.Element).getElement();
}

function patternOf(value: string | RegExp | undefined): Pattern {
  if (value === undefined) return null;
  return typeof value === 'string' ? value : { source: value.source, flags: value.flags };
}

/** Hovers first, like a mouse - some buttons only show then. */
async function click(element: WebdriverIO.Element) {
  await element.moveTo();
  await element.waitForClickable();
  await element.click();
}

/** Key by key - WebKitWebDriver drops a repeated key (the second "e" of "Three") within one sequence. */
async function typeKeys(browser: Browser, value: string) {
  for (const key of value) await browser.keys(key);
}

async function fill(element: WebdriverIO.Element, value: string) {
  await element.clearValue();
  await element.addValue(value);
}

/** Waits until the image in `element` has loaded - from the attachment files, through Tauri's asset protocol. */
async function imageLoaded(browser: Browser, element: WebdriverIO.Element) {
  await browser.waitUntil(
    () =>
      browser.execute(
        (button: unknown) => (button instanceof Element ? (button.querySelector('img')?.naturalWidth ?? 0) : 0) > 0,
        element,
      ),
    { timeout: 15_000, timeoutMsg: 'Image not loaded' },
  );
}

async function waitForCss(browser: Browser, selector: string) {
  await browser.$(selector).waitForExist({ timeout: 15_000 });
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function screenshot(browser: Browser, name: string) {
  if (screenshots !== undefined) await browser.saveScreenshot(join(screenshots, `${name}.png`));
}

let driver: ChildProcess | undefined;

/** tauri-driver, once for both launches - the app gets its environment: a fresh profile and the Flutter data. */
async function startDriver() {
  driver = spawn('tauri-driver', [], {
    stdio: ['ignore', 'inherit', 'inherit'],
    env: {
      ...process.env,
      XDG_DATA_HOME: join(home, 'data'),
      XDG_CONFIG_HOME: join(home, 'config'),
      XDG_CACHE_HOME: join(home, 'cache'),
      TURTLE_FLUTTER_DATA_DIR: flutterData,
    },
  });
  for (let i = 0; i < 50; i++) {
    if (
      await fetch('http://127.0.0.1:4444/status').then(
        (response) => response.ok,
        () => false,
      )
    )
      return;
    await sleep(100);
  }
  throw new Error('tauri-driver did not start');
}

async function launch(): Promise<Browser> {
  const browser = await remote({
    hostname: '127.0.0.1',
    port: 4444,
    logLevel: 'error',
    capabilities: { 'tauri:options': { application } },
  });
  current = browser;
  await browser.$('#root > :first-child').waitForExist({ timeout: 15_000 });
  await answerRequests(browser);
  return browser;
}

/**
 * The app asks these hooks (see e2e-hooks.ts in apps/turtle-base) before it reaches outside: the file dialog
 * picks the test PNG, Open Library's search finds "Dune" and every cover is the test PNG, Anthropic answers
 * the test prompt, and Google's token endpoint hands out tokens. The browser for Google's consent page agrees
 * right away, following the redirect back to the shell's loopback server.
 */
async function answerRequests(browser: Browser) {
  await browser.execute(installHooks, picture.toString('base64'));
}

async function createNamed(browser: Browser, button: string, name: string) {
  await click(await role(browser, 'button', button));
  await fill(await role(browser, 'textbox', 'Name', { exact: true }), name);
  await click(await role(browser, 'button', 'Create'));
}

async function addField(browser: Browser, name: string, type: string) {
  await fill(await role(browser, 'textbox', 'New field name'), name);
  await click(await role(browser, 'combobox', 'Field type', { nth: -1 }));
  await click(await role(browser, 'option', type, { exact: true }));
  await click(await role(browser, 'button', 'Add field'));
  await waitForCss(browser, `input[aria-label="Field name"][value="${name}"]`);
}

async function changeFieldType(browser: Browser, index: number, type: string) {
  await click(await role(browser, 'combobox', 'Field type', { nth: index }));
  await click(await role(browser, 'option', type, { exact: true }));
}

/** Fields, values, the option picker, tiles and type changes of the open, empty collection. */
async function editCollection(browser: Browser) {
  await click(await role(browser, 'button', 'Edit collection'));
  await addField(browser, 'Reps', 'Number');
  await addField(browser, 'Status', 'Select');
  await addField(browser, 'Photo', 'Files');
  // A new select's settings open right away, to add its options.
  await fill(await role(browser, 'textbox', 'New option'), 'Done');
  await browser.keys('Enter');
  await waitForCss(browser, 'input[aria-label="Option name"][value="Done"]');
  await screenshot(browser, '2a-edit-page');
  await click(await role(browser, 'button', 'Back'));

  await click(await role(browser, 'button', 'New entry'));
  await click(await role(browser, 'button', /^Name:/, { within: 'tbody' }));
  await fill(await role(browser, 'textbox', 'Name', { exact: true }), 'Squats');
  await browser.keys('Enter');
  await text(browser, 'Squats', 'tbody');

  await click(await role(browser, 'button', /^Reps:/, { within: 'tbody' }));
  const reps = await role(browser, 'textbox', 'Reps', { exact: true });
  await fill(reps, 'a dozen');
  await browser.keys('Enter');
  // Not a number: the input stays, flagged, and nothing is saved.
  await waitForCss(browser, 'input[aria-label="Reps"][aria-invalid="true"]');
  await fill(reps, '12');
  await browser.keys('Enter');
  await text(browser, /^12$/, 'tbody');

  await click(await role(browser, 'button', /^Status:/, { within: 'tbody' }));
  await click(await role(browser, 'button', 'Done', { within: '[role="dialog"]' }));
  await text(browser, 'Done', 'tbody');
  await screenshot(browser, '2b-table');

  await click(await role(browser, 'radio', 'Tiles'));
  await role(browser, 'button', 'Squats');
  await screenshot(browser, '2c-tiles');
  await click(await role(browser, 'radio', 'Table'));

  // Number to text keeps the values as they are; select to text rewrites option ids as names - after asking.
  await click(await role(browser, 'button', 'Edit collection'));
  await changeFieldType(browser, 0, 'Text');
  await changeFieldType(browser, 1, 'Text');
  await click(await role(browser, 'button', 'Change type', { within: '[role="alertdialog"]' }));
  await role(browser, 'combobox', 'Field type', { nth: 1, hasText: 'Text' });
  await click(await role(browser, 'button', 'Back'));
  await text(browser, 'Done', 'tbody');
  await text(browser, /^12$/, 'tbody');

  await editEntry(browser);
}

/** The entry's page: its field values above, text in the block editor - stored, so it's there when reopened. */
async function editEntry(browser: Browser) {
  await click(await role(browser, 'button', 'Open', { within: 'tbody' }));
  await waitForCss(browser, 'input[aria-label="Title"][value="Squats"]');
  await role(browser, 'term', undefined, { hasText: 'Reps' });
  await click(await role(browser, 'button', 'Icon'));
  await role(browser, 'button', 'Grinning Face', { exact: true });
  await screenshot(browser, '2d-emoji-picker');
  await fill(await role(browser, 'textbox', 'Search emoji'), 'biceps');
  await click(await role(browser, 'button', 'Flexed Biceps'));
  await role(browser, 'button', 'Icon', { hasText: '💪' });
  await click(await role(browser, 'button', 'Add file'));
  await role(browser, 'button', 'Open red.png', { has: 'img' });
  await click(await browser.$('.bn-editor').getElement());
  await typeKeys(browser, 'Three sets, slow on the way down.');
  await click(await role(browser, 'button', 'Attach file'));
  await imageLoaded(browser, await role(browser, 'button', 'Open red.png', { within: '.bn-editor' }));
  // Written after a short pause in typing.
  await sleep(1000);
  await screenshot(browser, '2d-page');

  await click(await role(browser, 'button', 'Back to collection'));
  await click(await role(browser, 'button', 'Open', { within: 'tbody' }));
  await text(browser, 'Three sets, slow on the way down.', '.bn-editor');
  await role(browser, 'button', 'Icon', { hasText: '💪' });
  await role(browser, 'button', 'Open red.png', { within: '.bn-editor' });
  await click(await role(browser, 'button', 'Back to collection'));
}

/** A big collection renders only what's in view - in the table and the tiles - and scrolls to its end. */
async function scrollThroughSeeds(browser: Browser) {
  await click(await role(browser, 'button', 'Seeds'));
  await text(browser, `${seedCount} entries`);
  const last = `Seed ${String(seedCount).padStart(4, '0')}`;
  for (const layout of ['Table', 'Tiles']) {
    await click(await role(browser, 'radio', layout));
    const first = await text(browser, 'Seed 0001');
    await screenshot(browser, `8-seeds-${layout.toLowerCase()}`);
    const rendered = await browser.execute(
      () =>
        [...document.querySelectorAll('*')].filter((element) => /^Seed \d{4}$/.test(element.textContent ?? '')).length,
    );
    if (rendered > 200) throw new Error(`${layout}: ${rendered} of ${seedCount} entries rendered`);
    const reachedEnd = await browser.execute(
      async (seed: unknown, lastSeed: string) => {
        let scroller = seed instanceof HTMLElement ? seed.parentElement : null;
        while (scroller !== null && scroller.scrollHeight <= scroller.clientHeight) scroller = scroller.parentElement;
        if (scroller === null) return false;
        const lastShown = () => [...document.querySelectorAll('*')].some((element) => element.textContent === lastSeed);
        for (let i = 0; i < 200 && !lastShown(); i++) {
          scroller.scrollTop += 4000;
          await new Promise((resolve) => requestAnimationFrame(resolve));
        }
        const shown = lastShown();
        scroller.scrollTop = 0;
        return shown;
      },
      first,
      last,
    );
    if (!reachedEnd) throw new Error(`${layout}: never scrolled to ${last}`);
  }
  await click(await role(browser, 'radio', 'Table'));
}

/** The Books plugin: added as a space, a book looked up, added - and opened, not added again, the second time. */
async function addBook(browser: Browser) {
  await click(await role(browser, 'button', 'Plugins'));
  await click(await role(browser, 'button', 'Add', { exact: true }));
  await click(await role(browser, 'button', 'Reading list'));
  for (const time of ['first', 'second']) {
    await click(await role(browser, 'button', 'Add book'));
    await fill(await role(browser, 'textbox', 'Search'), 'dune');
    await click(await role(browser, 'button', /^Dune/));
    await waitForCss(browser, 'input[aria-label="Title"][value="Dune"]');
    await text(browser, 'Frank Herbert');
    if (time === 'first') {
      // The cover is downloaded after the entry is there.
      await role(browser, 'button', 'Open 1-L.jpg', { has: 'img' });
      await screenshot(browser, '6-book');
    }
    await click(await role(browser, 'button', 'Back to collection'));
  }
  await text(browser, '1 entry');
}

try {
  await startDriver();
  const first = await launch();
  await text(first, 'No spaces yet');
  // Linux draws the title bar - the page doesn't draw one of its own.
  if (await first.$('[data-tauri-drag-region]').isExisting()) throw new Error('The page draws a title bar on Linux');
  await screenshot(first, '1-empty');
  await createNamed(first, 'Create your first space', 'Fitness');
  await role(first, 'combobox', 'Space', { hasText: 'Fitness' });

  await createNamed(first, 'New collection', 'Workouts');
  await role(first, 'button', 'Workouts');
  await text(first, 'No entries yet');
  await editCollection(first);
  await click(await role(first, 'button', 'New page'));
  await role(first, 'button', 'Untitled');
  await screenshot(first, '2-shell');

  await click(await role(first, 'button', 'Settings'));
  await click(await role(first, 'radio', 'Dark'));
  await click(await role(first, 'radio', 'Violet'));
  await waitForCss(first, 'html.dark[data-preset="violet"]');
  await fill(await role(first, 'textbox', 'Anthropic (Claude)'), 'sk-smoke');
  await first.keys('Enter');
  await text(first, 'Key saved');
  await click(await role(first, 'combobox', 'Default model'));
  await click(await role(first, 'option', 'Claude Sonnet 5.5'));
  await click(await role(first, 'button', 'Send test prompt'));
  await text(first, 'All good here.');
  await role(first, 'status', undefined, { hasText: 'Not connected' });
  await click(await role(first, 'button', 'Connect'));
  await role(first, 'status', undefined, { hasText: /^Connected$/ });
  await click(await role(first, 'button', 'Import from the Flutter app'));
  // No file counted: the picture is the one attached earlier - already in the store, stored once.
  await text(first, `Imported 1 space, 1 collection, ${seedCount + 1} pages.`);
  await screenshot(first, '3-settings-dark');
  await first.deleteSession();

  const second = await launch();
  await role(second, 'combobox', 'Space', { hasText: 'Fitness' });
  await click(await role(second, 'button', 'Workouts'));
  await waitForCss(second, 'html.dark[data-preset="violet"]');
  await screenshot(second, '4-restarted');
  // Still connected after the restart - the refresh token was kept.
  await click(await role(second, 'button', 'Settings'));
  await role(second, 'status', undefined, { hasText: /^Connected$/ });
  await click(await role(second, 'button', 'Disconnect'));
  await role(second, 'status', undefined, { hasText: 'Not connected' });
  await addBook(second);
  // The Flutter app's page, imported before the restart: its text in BlockNote, its picture in the store.
  await click(await role(second, 'combobox', 'Space'));
  await click(await role(second, 'option', 'Garden'));
  await click(await role(second, 'button', 'Tomatoes'));
  await role(second, 'heading', 'Planting', { within: '.bn-editor' });
  await imageLoaded(second, await role(second, 'button', 'Open seedling.png', { within: '.bn-editor', has: 'img' }));
  await screenshot(second, '7-imported');
  await scrollThroughSeeds(second);
  await click(await role(second, 'combobox', 'Space'));
  await click(await role(second, 'option', 'Fitness'));
  await click(await role(second, 'button', 'Workouts'));

  await second.setWindowSize(400, 760);
  await click(await role(second, 'button', 'Back'));
  await click(await role(second, 'button', 'Open sidebar'));
  await role(second, 'button', 'Workouts', { within: '[role="dialog"]' });
  await screenshot(second, '5-narrow-drawer');
  await second.deleteSession();
  console.log('Smoke test passed');
} catch (error) {
  if (current !== undefined) await screenshot(current, 'failure').catch(() => undefined);
  await current?.deleteSession().catch(() => undefined);
  throw error;
} finally {
  driver?.kill();
  rmSync(home, { recursive: true, force: true });
}
