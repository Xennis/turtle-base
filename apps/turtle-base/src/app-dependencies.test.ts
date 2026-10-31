import { readdirSync, readFileSync } from 'node:fs';

import * as v from 'valibot';
import { expect, test } from 'vite-plus/test';

const root = new URL('../../../', import.meta.url);
const packageJsonSchema = v.object({ name: v.string(), dependencies: v.optional(v.record(v.string(), v.string())) });

function packageJsonOf(path: string): v.InferOutput<typeof packageJsonSchema> {
  return v.parse(packageJsonSchema, JSON.parse(readFileSync(new URL(`${path}/package.json`, root), 'utf8')));
}

test('the app never depends on a plugin - users install those from the catalog', () => {
  const plugins = readdirSync(new URL('plugins', root)).map((folder) => packageJsonOf(`plugins/${folder}`).name);
  const dependencies = Object.keys(packageJsonOf('apps/turtle-base').dependencies ?? {});

  expect(plugins).toContain('@turtle-base/books');
  expect(dependencies.filter((name) => plugins.includes(name))).toStrictEqual([]);
});
