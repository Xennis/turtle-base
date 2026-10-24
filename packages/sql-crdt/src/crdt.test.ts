import { createNodeSqlDriver } from '@turtle-base/platform/testing';
import { array, assert, asyncProperty, constant, constantFrom, integer, oneof, record, string } from 'fast-check';
import { Kysely } from 'kysely';
import { describe, expect, test } from 'vite-plus/test';

import { MergeError, parseChangeset } from './changeset.ts';
import { addCrdtColumns, type CrdtColumns } from './crdt-plugin.ts';
import { Crdt } from './crdt.ts';
import { Hlc } from './hlc.ts';
import { SqlDriverDialect } from './sql-driver-dialect.ts';

interface TestDatabase {
  items: { id: string; name: string; note: string | null } & CrdtColumns;
}

interface TestNode {
  crdt: Crdt<TestDatabase>;
  db: Kysely<TestDatabase>;
  changed: string[][];
}

async function openNode(nodeId: string, driver = createNodeSqlDriver()): Promise<TestNode> {
  const plain = new Kysely<TestDatabase>({ dialect: new SqlDriverDialect(driver) });
  await addCrdtColumns(
    plain.schema
      .createTable('items')
      .ifNotExists()
      .addColumn('id', 'text', (column) => column.primaryKey())
      .addColumn('name', 'text', (column) => column.notNull())
      .addColumn('note', 'text'),
  ).execute();
  const changed: string[][] = [];
  const crdt = await Crdt.open(plain, { tables: ['items'], nodeId, onTablesChanged: (t) => changed.push([...t]) });
  return { crdt, db: plain.withPlugin(crdt.plugin), changed };
}

function write(node: TestNode, id: string, name: string) {
  return node.db
    .insertInto('items')
    .values({ id, name, note: null })
    .onConflict((conflict) => conflict.column('id').doUpdateSet({ name }))
    .execute();
}

function rows(node: TestNode) {
  return node.db.selectFrom('items').select(['id', 'name', 'hlc', 'node_id']).orderBy('id').execute();
}

/** Like SyncController: through JSON, as a file would be. */
async function sync(from: TestNode, to: TestNode) {
  const changeset = await from.crdt.getChangeset();
  await to.crdt.merge(parseChangeset(JSON.parse(JSON.stringify(changeset))));
}

describe('open', () => {
  test('gives an empty database the requested node id', async () => {
    const node = await openNode('a');

    expect(node.crdt.nodeId).toBe('a');
    expect(await node.crdt.getLastModified()).toBeUndefined();
  });

  test('continues the clock and node id of stored data', async () => {
    const driver = createNodeSqlDriver();
    const first = await openNode('a', driver);
    await write(first, '1', 'one');

    const reopened = await openNode('ignored', driver);

    expect(reopened.crdt.nodeId).toBe('a');
    expect(reopened.crdt.clock.canonicalTime).toEqual(first.crdt.clock.canonicalTime);
  });
});

describe('getChangeset', () => {
  test('filters by node and time', async () => {
    const a = await openNode('a');
    const b = await openNode('b');
    await write(a, '1', 'one');
    const afterFirst = await a.crdt.getLastModified();
    await write(a, '2', 'two');
    await write(b, '3', 'three');
    await sync(b, a);

    const own = await a.crdt.getChangeset({ onlyNodeId: 'a' });
    const others = await a.crdt.getChangeset({ exceptNodeId: 'a' });
    const newer = await a.crdt.getChangeset({ onlyNodeId: 'a', modifiedAfter: afterFirst });

    expect(own['items']?.map((row) => row['id'])).toEqual(['1', '2']);
    expect(others['items']?.map((row) => row['id'])).toEqual(['3']);
    expect(newer['items']?.map((row) => row['id'])).toEqual(['2']);
  });
});

describe('merge', () => {
  test('keeps the newer write of a row', async () => {
    const a = await openNode('a');
    const b = await openNode('b');
    await write(a, '1', 'from a');
    await sync(a, b);
    await write(b, '1', 'from b');

    await sync(b, a);
    await sync(a, b);

    expect(await rows(a)).toEqual(await rows(b));
    expect((await rows(a))[0]).toMatchObject({ name: 'from b', node_id: 'b' });
  });

  test('stamps merged rows with the own time and moves the clock', async () => {
    const a = await openNode('a');
    const b = await openNode('b');
    await write(b, '1', 'one');

    await sync(b, a);

    expect(a.crdt.clock.canonicalTime).toEqual(b.crdt.clock.canonicalTime.withNodeId('a'));
    expect((await a.crdt.getLastModified())?.nodeId).toBe('a');
    expect(a.changed).toEqual([['items']]);
  });

  test('rejects unknown tables and columns without merging anything', async () => {
    const a = await openNode('a');
    const hlc = new Hlc(Date.now(), 0, 'b').toString();
    const row = { id: '1', name: 'one', note: null, hlc, node_id: 'b', modified: hlc };

    await expect(a.crdt.merge({ items: [row], other: [row] })).rejects.toThrow(MergeError);
    await expect(a.crdt.merge({ items: [row, { ...row, id: '2', extra: 1 }] })).rejects.toThrow(MergeError);
    expect(await rows(a)).toEqual([]);
  });

  test('rejects records from the own node that are newer than its clock', async () => {
    const a = await openNode('a');
    const hlc = new Hlc(Date.now() + 1000, 0, 'a').toString();

    await expect(
      a.crdt.merge({ items: [{ id: '1', name: 'one', note: null, hlc, node_id: 'a', modified: hlc }] }),
    ).rejects.toThrow(MergeError);
  });

  test('converges whatever the order of writes and syncs', async () => {
    const nodeIds = ['a', 'b', 'c'] as const;
    const step = oneof(
      record({
        kind: constant('write' as const),
        node: integer({ min: 0, max: 2 }),
        id: constantFrom('1', '2', '3'),
        name: string({ maxLength: 3 }),
      }),
      record({
        kind: constant('sync' as const),
        from: integer({ min: 0, max: 2 }),
        to: integer({ min: 0, max: 2 }),
      }),
    );

    await assert(
      asyncProperty(array(step, { maxLength: 25 }), async (steps) => {
        const nodes = await Promise.all(nodeIds.map((id) => openNode(id)));
        const at = (i: number) => {
          const node = nodes[i];
          if (node === undefined) throw new Error(`No node ${i}`);
          return node;
        };
        for (const s of steps) {
          if (s.kind === 'write') await write(at(s.node), s.id, s.name);
          else if (s.from !== s.to) await sync(at(s.from), at(s.to));
        }
        // Everyone hears from everyone - twice, so merging again changes nothing.
        for (let round = 0; round < 2; round++) {
          for (const from of nodes) for (const to of nodes) if (from !== to) await sync(from, to);
        }
        const [first, ...others] = await Promise.all(nodes.map(rows));
        for (const other of others) expect(other).toEqual(first);
      }),
      { numRuns: 40 },
    );
  });
});
