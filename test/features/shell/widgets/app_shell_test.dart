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

  testWidgets('creates a space via the dropdown and renames the selection', (
    WidgetTester tester,
  ) async {
    final database = await pumpApp(tester);
    addTearDown(database.close);

    // "New space" lives inside the space dropdown's menu now, not a
    // separate button - open it, then pick that entry.
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New space'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Fitness');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Creating a space selects it, so it's now the dropdown's shown
    // value - "Default" is still around, just not the current one.
    expect(find.text('Fitness'), findsOneWidget);

    // Only one edit icon exists at a time now - for whichever space is
    // currently selected (Fitness, just created).
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Home');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Fitness'), findsNothing);
    expect(find.text('Home'), findsOneWidget);

    // "Default" is still there, just not selected - visible in the
    // dropdown's menu.
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Default'), findsOneWidget);
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
    expect(find.byType(DropdownButton<String>), findsOneWidget);

    // Going back returns to the grid, still with the sidebar visible.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(TrinaGrid), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('creates a page via the sidebar and opens it', (
    WidgetTester tester,
  ) async {
    final database = await pumpApp(tester);
    addTearDown(database.close);

    await tester.tap(find.byTooltip('New page'));
    // Creating a page does real FFI I/O (an insert), triggered from a
    // button handler rather than test code directly - same pattern as
    // Add row, needs runAsync to actually complete.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    // The new page is selected and open (shown as "Untitled" both in
    // the sidebar and as the Page-View's heading), while the sidebar
    // itself is still visible.
    expect(find.text('Untitled'), findsWidgets);
    expect(find.text('Default'), findsOneWidget);

    final pages = await database.select(database.pages).get();
    expect(pages, hasLength(1));
    expect(pages.single.collectionId, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
