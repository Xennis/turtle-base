import 'dart:async';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart';

import 'crdt_database_delegate.dart';

/// Opens a delayed [DatabaseConnection] backed by [CrdtDatabaseDelegate].
/// [resolvePath] is only invoked once the connection is actually used,
/// so callers can resolve async platform paths (e.g.
/// `getApplicationDocumentsDirectory()`) lazily.
(QueryExecutor, Future<CrdtDatabaseDelegate>) openCrdtDatabaseConnection(
  FutureOr<String?> Function() resolvePath,
) {
  final delegateCompleter = Completer<CrdtDatabaseDelegate>();
  final executor = DatabaseConnection.delayed(
    Future(() async {
      final path = await resolvePath();
      final delegate = CrdtDatabaseDelegate(path: path);
      delegateCompleter.complete(delegate);
      return DatabaseConnection(DelegatedDatabase(delegate));
    }),
  );
  return (executor, delegateCompleter.future);
}
