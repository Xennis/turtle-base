import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/shell/app_shell.dart';

void main() {
  testWidgets('shows the seeded default space in the sidebar', (
    WidgetTester tester,
  ) async {
    // closeStreamsSynchronously avoids a pending-timer failure: by
    // default a drift stream query stays open for one event loop turn
    // after the last subscriber unsubscribes, which flutter_test flags
    // as a leaked timer at teardown. See drift.simonbinder.eu/testing.
    final database = AppDatabase.withExecutor(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    addTearDown(database.close);

    // NativeDatabase does real FFI I/O for migration/seeding, which
    // needs runAsync() - but only for the real async work, not for
    // pumping (mixing the two hangs the test).
    await tester.runAsync(() => database.currentUserId());

    await tester.pumpWidget(
      AppScope(
        database: database,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Select a collection or page'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
