import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/shell/widgets/app_shell.dart';

/// An in-memory database for widget tests.
///
/// closeStreamsSynchronously avoids a pending-timer failure: by default
/// a drift stream query stays open for one event loop turn after the
/// last subscriber unsubscribes, which flutter_test flags as a leaked
/// timer at teardown. See drift.simonbinder.eu/testing.
AppDatabase newTestDatabase() {
  return AppDatabase.withExecutor(
    DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
  );
}

/// Sets up and pumps the full app against a fresh in-memory database.
///
/// NativeDatabase does real FFI I/O for migration/seeding, which needs
/// runAsync() - but only for the real async work, not for pumping
/// (mixing the two hangs the test).
Future<AppDatabase> pumpApp(WidgetTester tester) async {
  final database = newTestDatabase();
  await tester.runAsync(() => database.currentUserId());
  await tester.pumpWidget(
    AppScope(database: database, child: const MaterialApp(home: AppShell())),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return database;
}
