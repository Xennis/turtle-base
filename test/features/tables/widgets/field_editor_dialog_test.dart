import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/widgets/collection_view.dart';

import '../../../support/pump_app.dart';

void main() {
  testWidgets('Field-Editor: add, rename, retype, delete a field', (
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
