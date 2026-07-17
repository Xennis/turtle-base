import 'dart:async';

import 'package:drift/backends.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';

/// Bridges Drift to `sqlite_crdt` (see ARCHITECTURE.md's sync section).
///
/// sqlite_crdt does its CRDT tracking (hlc/node_id/modified columns,
/// soft-deletes via is_deleted) by rewriting SQL statements in Dart, not
/// via SQLite triggers - so it only tracks statements that actually go
/// through its own execute()/query() API. This delegate routes every
/// statement Drift issues through a [SqliteCrdt] instance instead of
/// straight to sqlite3, so our existing repositories (typed Drift
/// queries) get CRDT tracking without knowing anything about it.
///
/// Our own table definitions never declare the hlc/node_id/modified/
/// is_deleted columns themselves (unlike some sqlite_crdt users), so
/// unlike e.g. the drift_crdt package, CREATE TABLE statements don't
/// need to be rewritten before being handed to sqlite_crdt - it injects
/// those columns on its own.
class CrdtDatabaseDelegate extends DatabaseDelegate {
  CrdtDatabaseDelegate({this.path});

  /// Null opens an in-memory database (used by tests).
  final String? path;

  SqliteCrdt? _crdt;

  /// The underlying CRDT connection - only valid once [open] has run.
  SqliteCrdt get crdt =>
      _crdt ?? (throw StateError('CrdtDatabaseDelegate used before open()'));

  bool _isOpen = false;

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> open(QueryExecutorUser db) async {
    _crdt = path == null
        ? await SqliteCrdt.openInMemory()
        : await SqliteCrdt.open(path!);
    _isOpen = true;
  }

  @override
  Future<void> close() async {
    await _crdt?.close();
    _isOpen = false;
  }

  @override
  late final DbVersionDelegate versionDelegate = _CrdtVersionDelegate(this);

  @override
  late final TransactionDelegate transactionDelegate = _CrdtTransactionDelegate(
    this,
  );

  @override
  Future<void> runCustom(String statement, List<Object?> args) =>
      crdt.execute(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    await crdt.execute(statement, args);
    final result = await crdt.query('SELECT last_insert_rowid() AS id');
    return result.first['id'] as int;
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    await crdt.execute(statement, args);
    final result = await crdt.query('SELECT changes() AS c');
    return result.first['c'] as int;
  }

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) async {
    final rows = await crdt.query(statement, args);
    return QueryResult.fromRows(rows);
  }
}

class _CrdtVersionDelegate extends DynamicVersionDelegate {
  _CrdtVersionDelegate(this._delegate);

  final CrdtDatabaseDelegate _delegate;

  @override
  Future<int> get schemaVersion async {
    final result = await _delegate.crdt.query('PRAGMA user_version');
    return result.first.values.first as int;
  }

  @override
  Future<void> setSchemaVersion(int version) =>
      _delegate.crdt.execute('PRAGMA user_version = $version');
}

/// [CrdtApi] covers both the top-level [SqliteCrdt] and a transaction's
/// executor - a single query delegate implementation works for both.
class _CrdtQueryDelegate extends QueryDelegate {
  _CrdtQueryDelegate(this._api);

  final CrdtApi _api;

  @override
  Future<void> runCustom(String statement, List<Object?> args) =>
      _api.execute(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    await _api.execute(statement, args);
    final result = await _api.query('SELECT last_insert_rowid() AS id');
    return result.first['id'] as int;
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    await _api.execute(statement, args);
    final result = await _api.query('SELECT changes() AS c');
    return result.first['c'] as int;
  }

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) async {
    final rows = await _api.query(statement, args);
    return QueryResult.fromRows(rows);
  }
}

class _CrdtTransactionDelegate extends SupportedTransactionDelegate {
  _CrdtTransactionDelegate(this._delegate);

  final CrdtDatabaseDelegate _delegate;

  @override
  FutureOr<void> startTransaction(Future Function(QueryDelegate) run) {
    return _delegate.crdt.transaction((txn) => run(_CrdtQueryDelegate(txn)));
  }
}
