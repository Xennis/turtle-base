# @turtle-base/sql-crdt

A last-writer-wins CRDT on SQLite, ported from Dart's [`crdt`](https://pub.dev/packages/crdt) and [`sql_crdt`](https://github.com/cachapa/sql_crdt) packages that the Flutter app used. Every row carries a hybrid logical clock timestamp (`hlc`); merging a changeset from another device keeps, per row, whichever version has the newer timestamp.

- `Hlc`: the hybrid logical clock. Its string form (`<ISO time>-<counter>-<node id>`) sorts like the timestamps themselves, which SQL relies on.
- `SqlDriverDialect`: Kysely's SQLite dialect on top of `SqlDriver` from `@turtle-base/platform`, so the same typed queries run on Electron, Capacitor and in tests. It hands out its one connection to one caller at a time, so a transaction never picks up a query started elsewhere.
- `CrdtClock` and `CrdtPlugin`: a Kysely plugin that stamps every INSERT and UPDATE (including an upsert's update) on a CRDT table with the clock's next timestamp, by adding the CRDT columns (`hlc`, `node_id`, `modified`) to the query tree. DELETE on a CRDT table is rejected - rows are soft-deleted via `deleted_at` instead, so the deletion syncs like any other change. Raw `sql` writes bypass the plugin, so writes go through the query builder. `addCrdtColumns()` adds the columns in a migration; `CrdtColumns` types them as read-only.

Unlike `sql_crdt` there is no `is_deleted` column: nothing ever hard-deletes a CRDT row.
