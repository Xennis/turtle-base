// isNotNull clashes with flutter_test's matcher of the same name.
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/pages_repository.dart';
import 'package:turtle_base/features/shell/app_shell.dart';
import 'package:turtle_base/features/spaces/spaces_repository.dart';
import 'package:turtle_base/features/tables/collection_view.dart';
import 'package:turtle_base/features/tables/collections_repository.dart';
import 'package:turtle_base/features/tables/field_type.dart';
import 'package:turtle_base/features/tables/fields_repository.dart';

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

  testWidgets('collection view renders field columns and entry values', (
    WidgetTester tester,
  ) async {
    // Set up all data before pumping the widget at all, rather than
    // writing while StreamBuilders are already subscribed - the latter
    // hangs the test (drift's change notification doesn't seem to
    // cross back from runAsync's real zone into the fake test zone
    // cleanly once a widget tree is already listening).
    final database = AppDatabase.withExecutor(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    addTearDown(database.close);
    await tester.runAsync(() async {
      final spaceId = (await SpacesRepository(database).watchAll().first).single.id;
      final collections = CollectionsRepository(database);
      final fields = FieldsRepository(database);
      final pages = PagesRepository(database);

      final collectionId = await collections.create(spaceId: spaceId, name: 'Tasks');
      final priorityField = await fields.create(
        collectionId: collectionId,
        name: 'Priority',
        type: FieldType.text,
      );
      final entryId = await pages.create(
        spaceId: spaceId,
        collectionId: collectionId,
        title: 'Buy milk',
      );
      await pages.setPropertyValue(entryId, priorityField, 'High');
    });

    await tester.pumpWidget(
      AppScope(database: database, child: const MaterialApp(home: AppShell())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Tasks'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Priority'), findsOneWidget); // column header
    expect(find.text('Buy milk'), findsOneWidget); // title cell
    expect(find.text('High'), findsOneWidget); // property cell
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('editing a cell persists the change', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase.withExecutor(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    addTearDown(database.close);

    late String collectionId;
    late String priorityFieldId;
    late String entryId;
    await tester.runAsync(() async {
      final spaceId = (await SpacesRepository(database).watchAll().first).single.id;
      final collections = CollectionsRepository(database);
      final fields = FieldsRepository(database);
      final pages = PagesRepository(database);

      collectionId = await collections.create(spaceId: spaceId, name: 'Tasks');
      priorityFieldId = await fields.create(
        collectionId: collectionId,
        name: 'Priority',
        type: FieldType.text,
      );
      entryId = await pages.create(
        spaceId: spaceId,
        collectionId: collectionId,
        title: 'Buy milk',
      );
      await pages.setPropertyValue(entryId, priorityFieldId, 'Low');
    });

    late TrinaGridStateManager stateManager;
    await tester.pumpWidget(
      AppScope(
        database: database,
        child: MaterialApp(
          home: CollectionView(
            collectionId: collectionId,
            onLoaded: (event) => stateManager = event.stateManager,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Edit the "title" (built-in) and the "Priority" field cell
    // programmatically via the state manager, rather than simulating
    // the exact tap/keyboard gesture sequence TrinaGrid expects.
    final row = stateManager.rows.single;
    stateManager.changeCellValue(row.cells['title']!, 'Buy oat milk');
    stateManager.changeCellValue(row.cells[priorityFieldId]!, 'High');

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final entry = await (database.select(
      database.pages,
    )..where((p) => p.id.equals(entryId))).getSingle();
    expect(entry.title, 'Buy oat milk');
    expect(decodePageProperties(entry.properties)[priorityFieldId], 'High');
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('Field-Editor: add, rename, retype, delete a field', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase.withExecutor(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    addTearDown(database.close);

    late String collectionId;
    await tester.runAsync(() async {
      final spaceId = (await SpacesRepository(database).watchAll().first).single.id;
      collectionId = await CollectionsRepository(
        database,
      ).create(spaceId: spaceId, name: 'Tasks');
    });

    await tester.pumpWidget(
      AppScope(
        database: database,
        child: MaterialApp(home: CollectionView(collectionId: collectionId)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Add a field, defaulting to type text.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Add field'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Priority');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Priority'), findsOneWidget);
    var storedFields = await database.select(database.fields).get();
    expect(storedFields.single.name, 'Priority');
    expect(storedFields.single.type, 'text');

    // Rename it and change its type via the header's edit icon.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Urgency');
    await tester.tap(find.byType(DropdownButton<FieldType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Number').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    // The dialog's closing transition needs more than a couple of
    // short pumps to fully unmount (closeStreamsSynchronously already
    // fixed the drift-stream pending-timer issue, so pumpAndSettle is
    // safe here).
    await tester.pumpAndSettle();

    expect(find.text('Urgency'), findsOneWidget);
    expect(find.text('Priority'), findsNothing);
    storedFields = await database.select(database.fields).get();
    expect(storedFields.single.name, 'Urgency');
    expect(storedFields.single.type, 'number');

    // Delete it.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Urgency'), findsNothing);
    storedFields = await database.select(database.fields).get();
    expect(storedFields.single.deletedAt, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
