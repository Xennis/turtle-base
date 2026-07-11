import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/pages/widgets/page_properties_header.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/features/tables/data/relation_field.dart';

import '../../../support/pump_app.dart';

void main() {
  testWidgets('shows a labeled field for each field, with its current value', (
    WidgetTester tester,
  ) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String collectionId;
    late String pageId;
    await tester.runAsync(() async {
      final spaceId = (await SpacesRepository(database).watchAll().first).single.id;
      final collections = CollectionsRepository(database);
      final fields = FieldsRepository(database);
      final pages = PagesRepository(database);

      collectionId = await collections.create(spaceId: spaceId, name: 'Tasks');
      final priorityField = await fields.create(
        collectionId: collectionId,
        name: 'Priority',
        type: FieldType.text,
      );
      pageId = await pages.create(spaceId: spaceId, collectionId: collectionId);
      await pages.setPropertyValue(pageId, priorityField, 'High');
    });

    await tester.pumpWidget(
      AppScope(
        database: database,
        child: MaterialApp(
          home: Scaffold(
            body: PagePropertiesHeader(pageId: pageId, collectionId: collectionId),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Priority'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'High'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('editing a field value persists it', (WidgetTester tester) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String collectionId;
    late String pageId;
    late String priorityFieldId;
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
      pageId = await pages.create(spaceId: spaceId, collectionId: collectionId);
    });

    await tester.pumpWidget(
      AppScope(
        database: database,
        child: MaterialApp(
          home: Scaffold(
            body: PagePropertiesHeader(pageId: pageId, collectionId: collectionId),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(find.byType(TextField), 'Urgent');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final entry = await (database.select(
      database.pages,
    )..where((p) => p.id.equals(pageId))).getSingle();
    expect(decodePageProperties(entry.properties)[priorityFieldId], 'Urgent');
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a relation field shows related entries and picks new ones', (
    WidgetTester tester,
  ) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String collectionId;
    late String pageId;
    late String projectEntryId;
    late String relationFieldId;
    await tester.runAsync(() async {
      final spaceId = (await SpacesRepository(database).watchAll().first).single.id;
      final collections = CollectionsRepository(database);
      final fields = FieldsRepository(database);
      final pages = PagesRepository(database);

      collectionId = await collections.create(spaceId: spaceId, name: 'Tasks');
      final projectsId = await collections.create(spaceId: spaceId, name: 'Projects');
      projectEntryId = await pages.create(
        spaceId: spaceId,
        collectionId: projectsId,
        title: 'Website relaunch',
      );
      relationFieldId = await fields.create(
        collectionId: collectionId,
        name: 'Project',
        type: FieldType.relation,
        config: encodeRelationConfig(projectsId),
      );
      pageId = await pages.create(spaceId: spaceId, collectionId: collectionId);
    });

    await tester.pumpWidget(
      AppScope(
        database: database,
        child: MaterialApp(
          home: Scaffold(
            body: PagePropertiesHeader(pageId: pageId, collectionId: collectionId),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Website relaunch'), findsNothing);

    await tester.tap(find.widgetWithText(ActionChip, 'Add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Website relaunch'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    // Bounded pumps to let the dialog's exit animation finish, rather
    // than pumpAndSettle() - its search field autofocuses, and a
    // blinking-cursor timer can still be mid-dispose during the
    // transition (same class of issue as AppFlowyEditor's cursor).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Website relaunch'), findsOneWidget);
    final entry = await (database.select(
      database.pages,
    )..where((p) => p.id.equals(pageId))).getSingle();
    expect(
      decodeRelationValue(decodePageProperties(entry.properties)[relationFieldId]),
      [projectEntryId],
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
