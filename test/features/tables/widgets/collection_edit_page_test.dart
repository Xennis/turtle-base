import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/data/relation_field.dart';
import 'package:turtle_base/features/tables/widgets/collection_edit_page.dart';

import '../../../support/pump_app.dart';

void main() {
  testWidgets(
    'Edit collection page: rename the collection, add, rename, retype, delete a field',
    (WidgetTester tester) async {
      final database = newTestDatabase();
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
          child: MaterialApp(
            home: CollectionEditPage(collectionId: collectionId, onDone: () {}, onDeleted: () {}),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('No fields yet'), findsOneWidget);

      // Rename the collection via its own name field.
      await tester.enterText(find.widgetWithText(TextField, 'Tasks'), 'To-dos');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      var storedCollection = await database.select(database.collections).getSingle();
      expect(storedCollection.name, 'To-dos');

      // Add a field via the "new field" row, defaulting to text.
      await tester.enterText(find.byType(TextField).last, 'Priority');
      await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      var storedFields = await database.select(database.fields).get();
      expect(storedFields.single.name, 'Priority');
      expect(storedFields.single.type, 'text');
      expect(find.text('No fields yet'), findsNothing);

      // Rename it inline (the field row's TextField, identified by its
      // current value).
      await tester.enterText(find.widgetWithText(TextField, 'Priority'), 'Urgency');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      storedFields = await database.select(database.fields).get();
      expect(storedFields.single.name, 'Urgency');

      // Change its type via the row's dropdown (the field row's, not
      // the "new field" row's - it comes first in the list). The
      // Collection card's Icon row pushes it down, so ensure it's
      // scrolled into view before tapping.
      await tester.ensureVisible(find.byType(DropdownButton<FieldType>).first);
      await tester.tap(find.byType(DropdownButton<FieldType>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Number').last);
      await tester.pumpAndSettle();

      storedFields = await database.select(database.fields).get();
      expect(storedFields.single.type, 'number');

      // Delete it (not the collection's own delete button in the AppBar).
      await tester.tap(find.byTooltip('Delete field'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('No fields yet'), findsOneWidget);
      storedFields = await database.select(database.fields).get();
      expect(storedFields.single.deletedAt, isNotNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets('Edit collection page: customize the Name column label', (
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

    await tester.pumpWidget(
      AppScope(
        database: database,
        child: MaterialApp(
          home: CollectionEditPage(collectionId: collectionId, onDone: () {}, onDeleted: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Second TextField in the Collection card - the title-column
    // label, empty by default (shows "Name" only as a hint).
    await tester.enterText(find.byType(TextField).at(1), 'Task');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    var storedCollection = await database.select(database.collections).getSingle();
    expect(storedCollection.titleFieldLabel, 'Task');

    // Clearing it resets to the "Name" default rather than being
    // ignored (unlike the collection's own name field).
    await tester.enterText(find.byType(TextField).at(1), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    storedCollection = await database.select(database.collections).getSingle();
    expect(storedCollection.titleFieldLabel, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets(
    'a relation field requires and stores a target collection',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String targetCollectionId;
      await tester.runAsync(() async {
        final spaceId = (await SpacesRepository(database).watchAll().first).single.id;
        final collections = CollectionsRepository(database);
        collectionId = await collections.create(spaceId: spaceId, name: 'Tasks');
        targetCollectionId = await collections.create(spaceId: spaceId, name: 'Projects');
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: MaterialApp(
            home: CollectionEditPage(collectionId: collectionId, onDone: () {}, onDeleted: () {}),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.byType(TextField).last, 'Project');
      await tester.tap(find.byType(DropdownButton<FieldType>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Relation').last);
      await tester.pumpAndSettle();

      // Blocked until a target collection is picked - a relation field
      // without one is useless.
      final addButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add),
      );
      expect(addButton.onPressed, isNull);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Projects').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final storedFields = await database.select(database.fields).get();
      expect(storedFields.single.type, 'relation');
      expect(
        decodeRelationTargetCollectionId(storedFields.single.config),
        targetCollectionId,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
