import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/shell/widgets/app_shell.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/features/tables/data/relation_field.dart';
import 'package:turtle_base/features/tables/widgets/collection_view.dart';

import '../../../support/pump_app.dart';

void main() {
  testWidgets('collection view renders field columns and entry values', (
    WidgetTester tester,
  ) async {
    // Set up all data before pumping the widget at all, rather than
    // writing while StreamBuilders are already subscribed - the latter
    // hangs the test (drift's change notification doesn't seem to
    // cross back from runAsync's real zone into the fake test zone
    // cleanly once a widget tree is already listening).
    final database = newTestDatabase();
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
    // One more pump for the sidebar's default-space auto-select
    // (postFrameCallback -> notifyListeners -> rebuild) to settle.
    await tester.pump();

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
    final database = newTestDatabase();
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
            onEdit: () {},
            onOpenEntry: (_) {},
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

  testWidgets('double-tapping a row calls onOpenEntry with its page id', (
    WidgetTester tester,
  ) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String collectionId;
    late String entryId;
    await tester.runAsync(() async {
      final spaceId = (await SpacesRepository(database).watchAll().first).single.id;
      final collections = CollectionsRepository(database);
      final pages = PagesRepository(database);

      collectionId = await collections.create(spaceId: spaceId, name: 'Tasks');
      entryId = await pages.create(
        spaceId: spaceId,
        collectionId: collectionId,
        title: 'Buy milk',
      );
    });

    late TrinaGridStateManager stateManager;
    String? openedEntryId;
    await tester.pumpWidget(
      AppScope(
        database: database,
        child: MaterialApp(
          home: CollectionView(
            collectionId: collectionId,
            onEdit: () {},
            onOpenEntry: (id) => openedEntryId = id,
            onLoaded: (event) => stateManager = event.stateManager,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Simulate the double-tap directly through the widget's own
    // callback, same as _onCellChanged is exercised elsewhere via
    // changeCellValue - avoids reproducing TrinaGrid's exact gesture
    // sequence.
    final grid = tester.widget<TrinaGrid>(find.byType(TrinaGrid));
    final row = stateManager.rows.single;
    grid.onRowDoubleTap!(
      TrinaGridOnRowDoubleTapEvent(row: row, rowIdx: 0, cell: row.cells['title']!),
    );

    expect(openedEntryId, entryId);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('Add row creates a blank entry, edited inline afterwards', (
    WidgetTester tester,
  ) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String collectionId;
    await tester.runAsync(() async {
      final spaceId = (await SpacesRepository(database).watchAll().first).single.id;
      collectionId = await CollectionsRepository(
        database,
      ).create(spaceId: spaceId, name: 'Tasks');
    });

    late TrinaGridStateManager stateManager;
    await tester.pumpWidget(
      AppScope(
        database: database,
        child: MaterialApp(
          home: CollectionView(
            collectionId: collectionId,
            onEdit: () {},
            onOpenEntry: (_) {},
            onLoaded: (event) => stateManager = event.stateManager,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(await database.select(database.pages).get(), isEmpty);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Add row'));
    // _addRow does real FFI I/O (a stream's .first, then an insert),
    // triggered from a button handler rather than test code directly -
    // needs runAsync to actually complete within the pump budget.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final entries = await database.select(database.pages).get();
    expect(entries, hasLength(1));
    expect(entries.single.title, '');

    // Fill it in directly - no separate creation page.
    stateManager.changeCellValue(
      stateManager.rows.single.cells['title']!,
      'Buy milk',
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final entry = await database.select(database.pages).getSingle();
    expect(entry.title, 'Buy milk');
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('shows a relation field as resolved, read-only titles', (
    WidgetTester tester,
  ) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String collectionId;
    await tester.runAsync(() async {
      final spaceId = (await SpacesRepository(database).watchAll().first).single.id;
      final collections = CollectionsRepository(database);
      final fields = FieldsRepository(database);
      final pages = PagesRepository(database);

      collectionId = await collections.create(spaceId: spaceId, name: 'Tasks');
      final projectsId = await collections.create(spaceId: spaceId, name: 'Projects');
      final projectEntryId = await pages.create(
        spaceId: spaceId,
        collectionId: projectsId,
        title: 'Website relaunch',
      );
      final relationField = await fields.create(
        collectionId: collectionId,
        name: 'Project',
        type: FieldType.relation,
        config: encodeRelationConfig(projectsId),
      );
      final entryId = await pages.create(
        spaceId: spaceId,
        collectionId: collectionId,
        title: 'Buy milk',
      );
      await pages.setPropertyValue(entryId, relationField, [projectEntryId]);
    });

    await tester.pumpWidget(
      AppScope(
        database: database,
        child: MaterialApp(
          home: CollectionView(
            collectionId: collectionId,
            onEdit: () {},
            onOpenEntry: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Website relaunch'), findsOneWidget);
    final relationColumn = tester
        .widget<TrinaGrid>(find.byType(TrinaGrid))
        .columns
        .firstWhere((c) => c.title == 'Project');
    expect(relationColumn.readOnly, isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('grid uses a custom title column label if set', (
    WidgetTester tester,
  ) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String collectionId;
    await tester.runAsync(() async {
      final spaceId = (await SpacesRepository(database).watchAll().first).single.id;
      final collections = CollectionsRepository(database);
      collectionId = await collections.create(spaceId: spaceId, name: 'Tasks');
      await collections.setTitleFieldLabel(collectionId, 'Task');
    });

    await tester.pumpWidget(
      AppScope(
        database: database,
        child: MaterialApp(
          home: CollectionView(
            collectionId: collectionId,
            onEdit: () {},
            onOpenEntry: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Task'), findsOneWidget);
    expect(find.text('Name'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
