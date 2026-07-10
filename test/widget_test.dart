import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/shell/app_shell.dart';

/// Sets up and pumps the app against a fresh in-memory database.
///
/// closeStreamsSynchronously avoids a pending-timer failure: by default
/// a drift stream query stays open for one event loop turn after the
/// last subscriber unsubscribes, which flutter_test flags as a leaked
/// timer at teardown. See drift.simonbinder.eu/testing.
///
/// NativeDatabase does real FFI I/O for migration/seeding, which needs
/// runAsync() - but only for the real async work, not for pumping
/// (mixing the two hangs the test).
Future<AppDatabase> pumpApp(WidgetTester tester) async {
  final database = AppDatabase.withExecutor(
    DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
  );
  await tester.runAsync(() => database.currentUserId());
  await tester.pumpWidget(
    AppScope(database: database, child: const MaterialApp(home: AppShell())),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return database;
}

void main() {
  testWidgets('shows the seeded default space in the sidebar', (
    WidgetTester tester,
  ) async {
    final database = await pumpApp(tester);
    addTearDown(database.close);

    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Select a collection or page'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('creates and renames a space via the sidebar', (
    WidgetTester tester,
  ) async {
    final database = await pumpApp(tester);
    addTearDown(database.close);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Fitness');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Fitness'), findsOneWidget);

    // Two spaces exist now, so target the rename button of "Default"
    // specifically rather than any edit icon.
    final renameDefaultButton = find.descendant(
      of: find.widgetWithText(ExpansionTile, 'Default'),
      matching: find.byIcon(Icons.edit_outlined),
    );
    await tester.tap(renameDefaultButton);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Home');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Default'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
