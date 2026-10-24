import { join } from 'node:path';

import { _android as android, type AndroidDevice } from 'playwright';

// Walks through the installed debug build on the device ANDROID_SERIAL names - an emulator, since it clears
// the app's data first: a book looked up on Open Library (the real one - the shell's HTTP client is native,
// out of the test's reach) with its cover, a file from the system's picker, opening it with another app, and
// a secret and a pref kept over a restart. Run after `cap sync` and installing; an optional argument is a
// folder to put screenshots in.

const appId = 'org.xennis.apps.turtlebase';
const screenshots = process.argv[2];

/** A 16×16 red PNG, put into Downloads for the picker. */
const picture = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAFklEQVR4nGO4o6ZGEmIY1TCqYfhqAAATqigQ9JeO5gAAAABJRU5ErkJggg==',
  'base64',
);

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

async function screenshot(device: AndroidDevice, name: string) {
  if (screenshots !== undefined) await device.screenshot({ path: join(screenshots, `${name}.png`) });
}

/**
 * Taps the native view showing `label` (as text or description, optionally only with `resourceId`) - e.g. in
 * the system's file picker, outside the web view. False when there's none after `attempts` looks.
 */
async function tap(
  device: AndroidDevice,
  label: string,
  options: { resourceId?: string; attempts?: number } = {},
): Promise<boolean> {
  const id = options.resourceId === undefined ? '' : `[^>]*resource-id="${options.resourceId}"`;
  const pattern = new RegExp(
    `(?:text|content-desc)="${label}"${id}[^>]*bounds="\\[(\\d+),(\\d+)\\]\\[(\\d+),(\\d+)\\]"`,
  );
  for (let attempt = 0; attempt < (options.attempts ?? 10); attempt++) {
    // Native transitions (the picker opening, its drawer) settle first.
    await sleep(1000);
    // Not on shared storage - the picker would list the dump as a recent file.
    await device.shell('uiautomator dump /data/local/tmp/ui.xml');
    const match = pattern.exec((await device.shell('cat /data/local/tmp/ui.xml')).toString());
    if (match !== null) {
      const [x1 = 0, y1 = 0, x2 = 0, y2 = 0] = match.slice(1).map(Number);
      // Whole pixels - `input tap` ignores fractions silently.
      await device.shell(`input tap ${Math.round((x1 + x2) / 2)} ${Math.round((y1 + y2) / 2)}`);
      return true;
    }
  }
  return false;
}

// Named explicitly - the test clears the app's data, which must never happen on a phone that's attached too.
const serial = process.env['ANDROID_SERIAL'];
if (serial === undefined) throw new Error('Set ANDROID_SERIAL to the emulator to test on');
const device = (await android.devices()).find((candidate) => candidate.serial() === serial);
if (device === undefined) throw new Error(`No device ${serial} attached`);
await device.shell(`pm clear ${appId}`);
const opened = device.waitForEvent('webview');
await device.shell(`am start -n ${appId}/.MainActivity`);
const page = await (await opened).page();
page.on('pageerror', (error) => console.log(`[renderer error] ${error.message}`));

try {
  await page.getByText('No spaces yet').waitFor();
  await page.getByRole('button', { name: 'Open sidebar' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Plugins' }).click();
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  await page.getByRole('button', { name: 'Open sidebar' }).click();
  await screenshot(device, '1-drawer');
  await page.getByRole('dialog').getByRole('button', { name: 'Reading list' }).click();
  await page.getByRole('button', { name: 'Add book' }).click();
  await page.getByRole('textbox', { name: 'Search' }).fill('dune herbert');
  await page.getByRole('button', { name: /^Dune/ }).first().click();
  await page
    .getByRole('button', { name: /^Open .*\.jpg$/ })
    .locator('img')
    .waitFor();
  await screenshot(device, '2-book');

  // The system's file picker, which opens where it was left last time.
  await device.push(picture, '/sdcard/Download/red.png');
  await page.getByRole('button', { name: 'Attach file' }).click();
  if (!(await tap(device, 'red.png', { attempts: 3 }))) {
    await tap(device, 'Show roots');
    await tap(device, 'Downloads', { resourceId: 'android:id/title' });
    if (!(await tap(device, 'red.png'))) throw new Error('red.png not in the picker');
  }
  await page.locator('.bn-editor').getByRole('button', { name: 'Open red.png' }).click();
  await page.getByRole('button', { name: 'Open with…' }).click();
  await sleep(3000);
  const resumed = (await device.shell('dumpsys activity activities | grep -m1 ResumedActivity')).toString();
  if (resumed.includes(appId)) throw new Error(`No other app opened the file: ${resumed}`);
  await device.shell('input keyevent KEYCODE_BACK');
  await sleep(1500);
  await page.keyboard.press('Escape');

  await page.getByRole('button', { name: 'Back to collection' }).click();
  await page.getByRole('button', { name: 'Back', exact: true }).click();
  await page.getByRole('button', { name: 'Open sidebar' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Settings' }).click();
  await page.getByRole('radio', { name: 'Dark' }).click();
  await page.getByLabel('Anthropic (Claude)').fill('sk-smoke');
  await page.getByLabel('Anthropic (Claude)').press('Enter');
  await page.getByText('Key saved').waitFor();

  // Into the background first, like a user leaving the app - Android writes pending prefs then (they're saved
  // with apply()); a force-stop right away would drop them.
  await device.shell('input keyevent KEYCODE_HOME');
  await sleep(1500);
  await device.shell(`am force-stop ${appId}`);
  const reopened = device.waitForEvent('webview');
  await device.shell(`am start -n ${appId}/.MainActivity`);
  const restarted = await (await reopened).page();
  await restarted.locator('html.dark').waitFor({ state: 'attached' });
  await restarted.getByRole('button', { name: 'Open sidebar' }).click();
  await restarted.getByRole('dialog').getByRole('button', { name: 'Reading list' }).click();
  await restarted.getByText('Dune').first().waitFor();
  await restarted.getByRole('button', { name: 'Back', exact: true }).click();
  await restarted.getByRole('button', { name: 'Open sidebar' }).click();
  await restarted.getByRole('dialog').getByRole('button', { name: 'Settings' }).click();
  await restarted.getByText('Key saved').waitFor();
  await screenshot(device, '3-restarted');
  console.log('Smoke test passed');
} catch (error) {
  await screenshot(device, 'failure').catch(() => undefined);
  throw error;
} finally {
  await device.close();
}
