import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trina_grid/trina_grid.dart';

import '../../../support/pump_app.dart';

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

    await tester.tap(find.byTooltip('New space'));
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

  testWidgets('creates a collection with no user-defined fields yet', (
    WidgetTester tester,
  ) async {
    final database = await pumpApp(tester);
    addTearDown(database.close);

    await tester.tap(find.byTooltip('New collection'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Tasks');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Tasks'), findsOneWidget);

    await tester.tap(find.text('Tasks'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // No starter field: an entry's title (not a field) is the grid's
    // built-in first column, see CollectionView.
    expect(find.byType(TrinaGrid), findsOneWidget);
    final fields = await database.select(database.fields).get();
    expect(fields, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('sidebar stays visible while editing a collection', (
    WidgetTester tester,
  ) async {
    final database = await pumpApp(tester);
    addTearDown(database.close);

    await tester.tap(find.byTooltip('New collection'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Tasks');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Tasks'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit collection'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The edit page is showing (its own "Fields" section)...
    expect(find.text('Fields'), findsOneWidget);
    // ...while the sidebar, a sibling in the same Row, is still there.
    expect(find.text('Default'), findsOneWidget);
    expect(find.byTooltip('New space'), findsOneWidget);

    // Going back returns to the grid, still with the sidebar visible.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(TrinaGrid), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
