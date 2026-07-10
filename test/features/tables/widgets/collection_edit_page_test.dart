import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
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
            home: CollectionEditPage(collectionId: collectionId, onDone: () {}),
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
      // the "new field" row's - it comes first in the list).
      await tester.tap(find.byType(DropdownButton<FieldType>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Number').last);
      await tester.pumpAndSettle();

      storedFields = await database.select(database.fields).get();
      expect(storedFields.single.type, 'number');

      // Delete it.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('No fields yet'), findsOneWidget);
      storedFields = await database.select(database.fields).get();
      expect(storedFields.single.deletedAt, isNotNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
