import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
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
  testWidgets(
    'shows a labeled field for each field, with its current value',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String pageId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final fields = FieldsRepository(database);
        final pages = PagesRepository(database);

        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Tasks',
        );
        final priorityField = await fields.create(
          collectionId: collectionId,
          name: 'Priority',
          type: FieldType.text,
        );
        pageId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
        );
        await pages.setPropertyValue(pageId, priorityField, 'High');
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PagePropertiesHeader(
                pageId: pageId,
                collectionId: collectionId,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Priority'), findsOneWidget);
      expect(find.widgetWithText(ShadInput, 'High'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'editing a field value persists it',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String pageId;
      late String priorityFieldId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final fields = FieldsRepository(database);
        final pages = PagesRepository(database);

        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Tasks',
        );
        priorityFieldId = await fields.create(
          collectionId: collectionId,
          name: 'Priority',
          type: FieldType.text,
        );
        pageId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
        );
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PagePropertiesHeader(
                pageId: pageId,
                collectionId: collectionId,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.byType(ShadInput), 'Urgent');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final entry = await (database.select(
        database.pages,
      )..where((p) => p.id.equals(pageId))).getSingle();
      expect(decodePageProperties(entry.properties)[priorityFieldId], 'Urgent');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'a relation field shows related entries and picks new ones',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String pageId;
      late String projectEntryId;
      late String relationFieldId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final fields = FieldsRepository(database);
        final pages = PagesRepository(database);

        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Tasks',
        );
        final projectsId = await collections.create(
          spaceId: spaceId,
          name: 'Projects',
        );
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
        pageId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
        );
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PagePropertiesHeader(
                pageId: pageId,
                collectionId: collectionId,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Website relaunch'), findsNothing);

      await tester.tap(find.widgetWithText(ShadButton, 'Add'));
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
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Website relaunch'), findsOneWidget);
      final entry = await (database.select(
        database.pages,
      )..where((p) => p.id.equals(pageId))).getSingle();
      expect(
        decodeRelationValue(
          decodePageProperties(entry.properties)[relationFieldId],
        ),
        [projectEntryId],
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'shows an error for a non-numeric value in a number field',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String pageId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final fields = FieldsRepository(database);
        final pages = PagesRepository(database);

        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Tasks',
        );
        await fields.create(
          collectionId: collectionId,
          name: 'Quantity',
          type: FieldType.number,
        );
        pageId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
        );
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PagePropertiesHeader(
                pageId: pageId,
                collectionId: collectionId,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Enter a valid number'), findsNothing);

      await tester.enterText(find.byType(ShadInput), 'not a number');
      await tester.pump();

      expect(find.text('Enter a valid number'), findsOneWidget);

      await tester.enterText(find.byType(ShadInput), '42');
      await tester.pump();

      expect(find.text('Enter a valid number'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'shows an error immediately for an already-invalid stored number',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String pageId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final fields = FieldsRepository(database);
        final pages = PagesRepository(database);

        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Tasks',
        );
        final quantityFieldId = await fields.create(
          collectionId: collectionId,
          name: 'Quantity',
          type: FieldType.number,
        );
        pageId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
        );
        await pages.setPropertyValue(pageId, quantityFieldId, '3a');
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PagePropertiesHeader(
                pageId: pageId,
                collectionId: collectionId,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // No typing happened yet - the error must show up from the
      // stored value alone.
      expect(find.text('Enter a valid number'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'shows an error for an invalid value in a date field',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String pageId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final fields = FieldsRepository(database);
        final pages = PagesRepository(database);

        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Tasks',
        );
        await fields.create(
          collectionId: collectionId,
          name: 'Due',
          type: FieldType.date,
        );
        pageId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
        );
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PagePropertiesHeader(
                pageId: pageId,
                collectionId: collectionId,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Enter a valid date'), findsNothing);

      await tester.enterText(find.byType(ShadInput), 'not a date');
      await tester.pump();

      expect(find.textContaining('Enter a valid date'), findsOneWidget);

      await tester.enterText(find.byType(ShadInput), '2026-07-18');
      await tester.pump();

      expect(find.textContaining('Enter a valid date'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'shows an error immediately for an already-invalid stored date',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String pageId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final fields = FieldsRepository(database);
        final pages = PagesRepository(database);

        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Tasks',
        );
        final dueFieldId = await fields.create(
          collectionId: collectionId,
          name: 'Due',
          type: FieldType.date,
        );
        pageId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
        );
        await pages.setPropertyValue(pageId, dueFieldId, 'not a date');
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PagePropertiesHeader(
                pageId: pageId,
                collectionId: collectionId,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Enter a valid date'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'shows an error for an invalid value in a URL field',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String pageId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final fields = FieldsRepository(database);
        final pages = PagesRepository(database);

        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Tasks',
        );
        await fields.create(
          collectionId: collectionId,
          name: 'Website',
          type: FieldType.url,
        );
        pageId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
        );
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PagePropertiesHeader(
                pageId: pageId,
                collectionId: collectionId,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Enter a valid URL'), findsNothing);

      await tester.enterText(find.byType(ShadInput), 'not a url');
      await tester.pump();

      expect(find.textContaining('Enter a valid URL'), findsOneWidget);

      await tester.enterText(find.byType(ShadInput), 'anthropic.com');
      await tester.pump();

      expect(find.textContaining('Enter a valid URL'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'shows an error immediately for an already-invalid stored URL',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String pageId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final fields = FieldsRepository(database);
        final pages = PagesRepository(database);

        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Tasks',
        );
        final websiteFieldId = await fields.create(
          collectionId: collectionId,
          name: 'Website',
          type: FieldType.url,
        );
        pageId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
        );
        await pages.setPropertyValue(pageId, websiteFieldId, 'not a url');
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PagePropertiesHeader(
                pageId: pageId,
                collectionId: collectionId,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Enter a valid URL'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'does not persist an invalid number, only a subsequent valid one',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String pageId;
      late String quantityFieldId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final fields = FieldsRepository(database);
        final pages = PagesRepository(database);

        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Tasks',
        );
        quantityFieldId = await fields.create(
          collectionId: collectionId,
          name: 'Quantity',
          type: FieldType.number,
        );
        pageId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
        );
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PagePropertiesHeader(
                pageId: pageId,
                collectionId: collectionId,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.byType(ShadInput), 'not a number');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      var entry = await (database.select(
        database.pages,
      )..where((p) => p.id.equals(pageId))).getSingle();
      expect(decodePageProperties(entry.properties)[quantityFieldId], isNull);

      await tester.enterText(find.byType(ShadInput), '42');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      entry = await (database.select(
        database.pages,
      )..where((p) => p.id.equals(pageId))).getSingle();
      expect(decodePageProperties(entry.properties)[quantityFieldId], '42');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'does not persist an invalid date, only a subsequent valid one',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String pageId;
      late String dueFieldId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final fields = FieldsRepository(database);
        final pages = PagesRepository(database);

        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Tasks',
        );
        dueFieldId = await fields.create(
          collectionId: collectionId,
          name: 'Due',
          type: FieldType.date,
        );
        pageId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
        );
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PagePropertiesHeader(
                pageId: pageId,
                collectionId: collectionId,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.byType(ShadInput), 'not a date');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      var entry = await (database.select(
        database.pages,
      )..where((p) => p.id.equals(pageId))).getSingle();
      expect(decodePageProperties(entry.properties)[dueFieldId], isNull);

      await tester.enterText(find.byType(ShadInput), '2026-07-18');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      entry = await (database.select(
        database.pages,
      )..where((p) => p.id.equals(pageId))).getSingle();
      expect(decodePageProperties(entry.properties)[dueFieldId], '2026-07-18');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'does not persist an invalid URL, only a subsequent valid one',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String pageId;
      late String websiteFieldId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final fields = FieldsRepository(database);
        final pages = PagesRepository(database);

        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Tasks',
        );
        websiteFieldId = await fields.create(
          collectionId: collectionId,
          name: 'Website',
          type: FieldType.url,
        );
        pageId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
        );
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PagePropertiesHeader(
                pageId: pageId,
                collectionId: collectionId,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.byType(ShadInput), 'not a url');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      var entry = await (database.select(
        database.pages,
      )..where((p) => p.id.equals(pageId))).getSingle();
      expect(decodePageProperties(entry.properties)[websiteFieldId], isNull);

      await tester.enterText(find.byType(ShadInput), 'anthropic.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      entry = await (database.select(
        database.pages,
      )..where((p) => p.id.equals(pageId))).getSingle();
      expect(
        decodePageProperties(entry.properties)[websiteFieldId],
        'anthropic.com',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
