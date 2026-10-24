# @turtle-base/sql-crdt

A last-writer-wins CRDT on SQLite, ported from Dart's [`crdt`](https://pub.dev/packages/crdt) and [`sql_crdt`](https://github.com/cachapa/sql_crdt) packages that the Flutter app used. Every row carries a hybrid logical clock timestamp (`hlc`); merging a changeset from another device keeps, per row, whichever version has the newer timestamp.

- `Hlc`: the hybrid logical clock. Its string form (`<ISO time>-<counter>-<node id>`) sorts like the timestamps themselves, which SQL relies on.
- `SqlDriverDialect`: Kysely's SQLite dialect on top of `SqlDriver` from `@turtle-base/platform`, so the same typed queries run on Electron, Capacitor and in tests. It hands out its one connection to one caller at a time, so a transaction never picks up a query started elsewhere.
