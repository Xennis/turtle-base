import { expect, test } from 'vite-plus/test';

import { ensureSyncFormat, SyncFormatTooNewError, syncFormatVersion } from './sync-format.ts';

async function writesFor(found: number | undefined): Promise<number[]> {
  const written: number[] = [];
  await ensureSyncFormat({
    read: () => Promise.resolve(found),
    write: (version) => {
      written.push(version);
      return Promise.resolve();
    },
  });
  return written;
}

test('writes the version when there is none yet', async () => {
  expect(await writesFor(undefined)).toEqual([syncFormatVersion]);
});

test('upgrades an older version', async () => {
  expect(await writesFor(syncFormatVersion - 1)).toEqual([syncFormatVersion]);
});

test('leaves the same version alone', async () => {
  expect(await writesFor(syncFormatVersion)).toEqual([]);
});

test('refuses a newer version', async () => {
  await expect(writesFor(syncFormatVersion + 1)).rejects.toBeInstanceOf(SyncFormatTooNewError);
});
