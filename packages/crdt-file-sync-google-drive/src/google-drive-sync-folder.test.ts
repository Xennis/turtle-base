import { describe, expect, test } from 'vite-plus/test';

import { resumableThreshold } from './drive-client.ts';
import { GoogleDriveSyncFolder } from './google-drive-sync-folder.ts';
import { FakeDrive } from './testing.ts';

function folderOn(drive: FakeDrive) {
  return new GoogleDriveSyncFolder({ fetch: drive.fetch, accessToken: () => Promise.resolve('token') });
}

function streamOf(bytes: number[]) {
  return new Blob([new Uint8Array(bytes)]).stream();
}

const bytesOf = (text: string) => new TextEncoder().encode(text);

describe('changesets', () => {
  test('upload() creates the folder path and a per-device subfolder lazily', async () => {
    const drive = new FakeDrive();

    await folderOn(drive).changesets.upload('node-a/1.json', bytesOf('hello'));

    expect(drive.folderAt(['turtle-base-sync', 'changesets', 'node-a']).name).toBe('node-a');
  });

  test('list() returns names for every device folder', async () => {
    const drive = new FakeDrive();
    await folderOn(drive).changesets.upload('node-a/1.json', new Uint8Array([1]));
    await folderOn(drive).changesets.upload('node-b/1.json', new Uint8Array([2]));

    // A fresh instance (no cached folder ids) still finds both devices' files.
    const names = await folderOn(drive).changesets.list();

    expect(names.toSorted()).toEqual(['node-a/1.json', 'node-b/1.json']);
  });

  test('list() follows nextPageToken past the first page', async () => {
    const drive = new FakeDrive(2);
    const folder = folderOn(drive);
    for (let i = 0; i < 5; i++) await folder.changesets.upload(`node-a/${i}.json`, new Uint8Array([i]));
    for (const node of ['node-b', 'node-c']) await folder.changesets.upload(`${node}/0.json`, new Uint8Array([0]));

    expect(await folderOn(drive).changesets.list()).toHaveLength(7);
  });

  test('upload() then download() round-trips the bytes', async () => {
    const drive = new FakeDrive();
    const bytes = bytesOf('{"spaces":[]}');

    await folderOn(drive).changesets.upload('node-a/1.json', bytes);

    expect(await folderOn(drive).changesets.download('node-a/1.json')).toEqual(bytes);
  });

  test('two uploads from the same device reuse the same device folder', async () => {
    const drive = new FakeDrive();
    const folder = folderOn(drive);

    await Promise.all([
      folder.changesets.upload('node-a/1.json', new Uint8Array([1])),
      folder.changesets.upload('node-a/2.json', new Uint8Array([2])),
    ]);

    expect(drive.folders.filter((f) => f.name === 'node-a')).toHaveLength(1);
  });

  test('list() ignores the files folder and format file next to it', async () => {
    const drive = new FakeDrive();
    const folder = folderOn(drive);
    await folder.changesets.upload('node-a/1.json', new Uint8Array([1]));
    await folder.files.upload('sha256-abc', streamOf([1, 2]), 2);
    await folder.writeFormatVersion(2);

    expect(await folder.changesets.list()).toEqual(['node-a/1.json']);
  });
});

describe('files', () => {
  test('upload() stores flat in the files folder', async () => {
    const drive = new FakeDrive();

    await folderOn(drive).files.upload('sha256-abc', streamOf([1, 2, 3]), 3);

    expect(drive.filesIn(drive.folderAt(['turtle-base-sync', 'files'])).map((f) => [f.name, [...f.bytes]])).toEqual([
      ['sha256-abc', [1, 2, 3]],
    ]);
  });

  test('upload() takes the resumable route for large files', async () => {
    const drive = new FakeDrive();
    const large = new Uint8Array(resumableThreshold).fill(7);

    await folderOn(drive).files.upload('sha256-large', new Blob([large]).stream(), large.length);

    const [file] = drive.filesIn(drive.folderAt(['turtle-base-sync', 'files']));
    expect(file?.name).toBe('sha256-large');
    expect(file?.bytes.length).toBe(resumableThreshold);
  });

  test('list() returns every name, across pages', async () => {
    const drive = new FakeDrive(2);
    const folder = folderOn(drive);
    for (let i = 0; i < 5; i++) await folder.files.upload(`sha256-${i}`, streamOf([i]), 1);

    expect(await folderOn(drive).files.list()).toEqual(new Set([0, 1, 2, 3, 4].map((i) => `sha256-${i}`)));
  });

  test('download() streams the uploaded bytes, also from a fresh instance', async () => {
    const drive = new FakeDrive();
    await folderOn(drive).files.upload('sha256-abc', streamOf([4, 5, 6]), 3);

    const stream = await folderOn(drive).files.download('sha256-abc');

    expect(new Uint8Array(await new Response(stream).arrayBuffer())).toEqual(new Uint8Array([4, 5, 6]));
  });
});

describe('format', () => {
  test('readFormatVersion() is undefined until written', async () => {
    expect(await folderOn(new FakeDrive()).readFormatVersion()).toBeUndefined();
  });

  test('writeFormatVersion() creates format.json once and updates it after', async () => {
    const drive = new FakeDrive();
    const folder = folderOn(drive);

    await folder.writeFormatVersion(2);
    await folder.writeFormatVersion(3);

    expect(drive.filesIn(drive.folderAt(['turtle-base-sync'])).filter((f) => f.name === 'format.json')).toHaveLength(1);
    expect(await folderOn(drive).readFormatVersion()).toBe(3);
  });
});

test('sends the access token with every request', async () => {
  const folder = new GoogleDriveSyncFolder({
    fetch: new FakeDrive().fetch,
    accessToken: () => Promise.resolve('wrong'),
  });

  await expect(folder.readFormatVersion()).rejects.toThrow(/401/);
});
