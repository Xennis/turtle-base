import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/data/blocks_repository.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/pages/widgets/page_detail_view.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';

import '../../../support/pump_app.dart';

void main() {
  testWidgets(
    'shows the page title and its blocks',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String pageId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        // Reuse the same repository the app uses to create the page, so
        // the title/space wiring matches; the AppDatabase is shared.
        final pagesTable = database.pages;
        final now = DateTime.now();
        pageId = 'page_1';
        await database
            .into(pagesTable)
            .insert(
              PagesCompanion.insert(
                id: pageId,
                spaceId: spaceId,
                title: 'My notes',
                position: 0,
                createdAt: now,
                updatedAt: now,
                createdBy: await database.currentUserId(),
                updatedBy: await database.currentUserId(),
              ),
            );
        final blocks = BlocksRepository(database);
        await blocks.create(
          pageId: pageId,
          type: 'paragraph',
          content: '{"delta": [{"insert": "Hello world"}]}',
        );
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          // AppShell normally provides the Scaffold/Material ancestor
          // PageDetailView's TextField needs - reproduce that here.
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PageDetailView(pageId: pageId, onDeleted: () {}),
            ),
          ),
        ),
      );
      // PageDetailView's own initial load (didChangeDependencies) does
      // real FFI I/O too, kicked off by the framework rather than test
      // code or a button handler - same runAsync requirement applies.
      // pumpAndSettle() hangs here - AppFlowyEditor apparently runs a
      // periodic timer (e.g. cursor blink) that never lets it settle.
      // Bounded pumps instead, same as most other tests in this project.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.widgetWithText(ShadInput, 'My notes'), findsOneWidget);
      // find.textContaining doesn't match here - AppFlowyEditor renders
      // the paragraph as a RichText whose text is a TextSpan tree, and
      // toPlainText() (used below) walks it correctly where the finder's
      // own matching apparently doesn't. Confirmed by inspecting the
      // widget tree directly during development.
      final hasHelloWorld = tester
          .widgetList<RichText>(find.byType(RichText))
          .any(
            (richText) => richText.text.toPlainText().contains('Hello world'),
          );
      expect(hasHelloWorld, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'renders an empty page without crashing',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String pageId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final now = DateTime.now();
        pageId = 'page_1';
        await database
            .into(database.pages)
            .insert(
              PagesCompanion.insert(
                id: pageId,
                spaceId: spaceId,
                title: '',
                position: 0,
                createdAt: now,
                updatedAt: now,
                createdBy: await database.currentUserId(),
                updatedBy: await database.currentUserId(),
              ),
            );
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PageDetailView(pageId: pageId, onDeleted: () {}),
            ),
          ),
        ),
      );
      // pumpAndSettle() hangs here - AppFlowyEditor apparently runs a
      // periodic timer (e.g. cursor blink) that never lets it settle.
      // Bounded pumps instead, same as most other tests in this project.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // "Untitled" is the title field's placeholder (empty title), not
      // its actual text content - check the controller directly too.
      expect(find.text('Untitled'), findsOneWidget);
      final titleField = tester.widget<ShadInput>(find.byType(ShadInput).first);
      expect(titleField.controller?.text, isEmpty);
      expect(tester.takeException(), isNull);
      // A freestanding page (no collectionId) has no properties to show
      // and nothing to go "back" to.
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'shows a back button and properties header for a collection entry',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String pageId;
      late String collectionId;
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
          title: 'Buy milk',
        );
        await pages.setPropertyValue(pageId, priorityField, 'High');
      });

      String? openedCollectionId;
      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PageDetailView(
                pageId: pageId,
                onOpenCollection: (id) => openedCollectionId = id,
                onDeleted: () {},
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      // PagePropertiesHeader mounts its own streams once PageDetailView
      // itself has already loaded, needing a second real-time wait, same
      // reasoning as the app_shell_test.dart page-navigation test.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.widgetWithText(ShadInput, 'Buy milk'), findsOneWidget);
      expect(find.text('Priority'), findsOneWidget);
      expect(find.widgetWithText(ShadInput, 'High'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      expect(openedCollectionId, collectionId);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'deleting an entry soft-deletes it and returns to the collection',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String pageId;
      late String collectionId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        collectionId = await CollectionsRepository(
          database,
        ).create(spaceId: spaceId, name: 'Tasks');
        pageId = await PagesRepository(database).create(
          spaceId: spaceId,
          collectionId: collectionId,
          title: 'Buy milk',
        );
      });

      String? openedCollectionId;
      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            Scaffold(
              body: PageDetailView(
                pageId: pageId,
                onOpenCollection: (id) => openedCollectionId = id,
                onDeleted: () {},
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byTooltip('Delete entry'));
      await tester.pump();
      await tester.tap(find.text('Delete'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(openedCollectionId, collectionId);
      final entry = await (database.select(
        database.pages,
      )..where((p) => p.id.equals(pageId))).getSingle();
      expect(entry.deletedAt, isNotNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
