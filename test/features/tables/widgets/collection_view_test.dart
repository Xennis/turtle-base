// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
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
  testWidgets(
    'collection view renders field columns and entry values',
    (WidgetTester tester) async {
      // Set up all data before pumping the widget at all, rather than
      // writing while StreamBuilders are already subscribed - the latter
      // hangs the test (drift's change notification doesn't seem to
      // cross back from runAsync's real zone into the fake test zone
      // cleanly once a widget tree is already listening).
      final database = newTestDatabase();
      addTearDown(database.close);
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final fields = FieldsRepository(database);
        final pages = PagesRepository(database);

        final collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Tasks',
        );
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
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(const AppShell()),
        ),
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
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'editing a cell persists the change',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String priorityFieldId;
      late String entryId;
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
          child: wrapWithAppLocalizations(
            CollectionView(
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

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final entry = await (database.select(
        database.pages,
      )..where((p) => p.id.equals(entryId))).getSingle();
      expect(entry.title, 'Buy oat milk');
      expect(decodePageProperties(entry.properties)[priorityFieldId], 'High');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'double-tapping a row calls onOpenEntry with its page id',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String entryId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final pages = PagesRepository(database);

        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Tasks',
        );
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
          child: wrapWithAppLocalizations(
            CollectionView(
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
        TrinaGridOnRowDoubleTapEvent(
          row: row,
          rowIdx: 0,
          cell: row.cells['title']!,
        ),
      );

      expect(openedEntryId, entryId);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Add row creates a blank entry, edited inline afterwards',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        collectionId = await CollectionsRepository(
          database,
        ).create(spaceId: spaceId, name: 'Tasks');
      });

      late TrinaGridStateManager stateManager;
      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            CollectionView(
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

      await tester.tap(find.widgetWithText(ShadButton, 'Add row'));
      // _addRow does real FFI I/O (a stream's .first, then an insert),
      // triggered from a button handler rather than test code directly -
      // needs runAsync to actually complete within the pump budget.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
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
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final entry = await database.select(database.pages).getSingle();
      expect(entry.title, 'Buy milk');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'shows a relation field as resolved, read-only titles',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

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
        final projectsId = await collections.create(
          spaceId: spaceId,
          name: 'Projects',
        );
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
          child: wrapWithAppLocalizations(
            CollectionView(
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
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'grid uses a custom title column label if set',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Tasks',
        );
        await collections.setTitleFieldLabel(collectionId, 'Task');
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            CollectionView(
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
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'shows a URL field value as a tappable link',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final fields = FieldsRepository(database);
        final pages = PagesRepository(database);

        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Links',
        );
        final urlFieldId = await fields.create(
          collectionId: collectionId,
          name: 'Website',
          type: FieldType.url,
        );
        final entryId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
          title: 'Anthropic',
        );
        await pages.setPropertyValue(entryId, urlFieldId, 'anthropic.com');
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            CollectionView(
              collectionId: collectionId,
              onEdit: () {},
              onOpenEntry: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('anthropic.com'), findsOneWidget);
      final linkText = tester.widget<Text>(find.text('anthropic.com'));
      expect(linkText.style?.decoration, TextDecoration.underline);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'rejects an invalid URL and keeps the previous value',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String urlFieldId;
      late String entryId;
      await tester.runAsync(() async {
        final spaceId = await SpacesRepository(database).create(name: 'Space');
        final collections = CollectionsRepository(database);
        final fields = FieldsRepository(database);
        final pages = PagesRepository(database);

        collectionId = await collections.create(
          spaceId: spaceId,
          name: 'Links',
        );
        urlFieldId = await fields.create(
          collectionId: collectionId,
          name: 'Website',
          type: FieldType.url,
        );
        entryId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
          title: 'Anthropic',
        );
        await pages.setPropertyValue(entryId, urlFieldId, 'anthropic.com');
      });

      late TrinaGridStateManager stateManager;
      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            CollectionView(
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

      final row = stateManager.rows.single;
      stateManager.changeCellValue(row.cells[urlFieldId]!, 'not a url');
      await tester.pump();

      expect(row.cells[urlFieldId]!.value, 'anthropic.com');
      final entry = await (database.select(
        database.pages,
      )..where((p) => p.id.equals(entryId))).getSingle();
      expect(
        decodePageProperties(entry.properties)[urlFieldId],
        'anthropic.com',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'formats a date field value for display',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

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
        final dueFieldId = await fields.create(
          collectionId: collectionId,
          name: 'Due',
          type: FieldType.date,
        );
        final entryId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
          title: 'Buy milk',
        );
        // A legacy ISO-8601 value (as if typed before date fields had a
        // dedicated column type) should still be reformatted for display.
        await pages.setPropertyValue(
          entryId,
          dueFieldId,
          '2026-07-18T00:00:00.000',
        );
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            CollectionView(
              collectionId: collectionId,
              onEdit: () {},
              onOpenEntry: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('2026-07-18'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'rejects an invalid date and keeps the previous value',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

      late String collectionId;
      late String dueFieldId;
      late String entryId;
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
        entryId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
          title: 'Buy milk',
        );
        await pages.setPropertyValue(entryId, dueFieldId, '2026-07-18');
      });

      late TrinaGridStateManager stateManager;
      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            CollectionView(
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

      final row = stateManager.rows.single;
      stateManager.changeCellValue(row.cells[dueFieldId]!, 'not a date');
      await tester.pump();

      expect(row.cells[dueFieldId]!.value, '2026-07-18');
      final entry = await (database.select(
        database.pages,
      )..where((p) => p.id.equals(entryId))).getSingle();
      expect(decodePageProperties(entry.properties)[dueFieldId], '2026-07-18');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'shows nothing for an empty number field, not "0"',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

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
        await fields.create(
          collectionId: collectionId,
          name: 'Quantity',
          type: FieldType.number,
        );
        await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
          title: 'Buy milk',
        );
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            CollectionView(
              collectionId: collectionId,
              onEdit: () {},
              onOpenEntry: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('0'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'flags a non-numeric stored value in a number field',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

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
        final quantityFieldId = await fields.create(
          collectionId: collectionId,
          name: 'Quantity',
          type: FieldType.number,
        );
        final entryId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
          title: 'Buy milk',
        );
        // Only possible via the entry's Page-View, which warns but
        // doesn't block saving invalid numbers (see
        // page_properties_header_test.dart) - the grid still has to
        // show it as an error rather than silently coercing it.
        await pages.setPropertyValue(entryId, quantityFieldId, '3a');
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            CollectionView(
              collectionId: collectionId,
              onEdit: () {},
              onOpenEntry: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('3a'), findsOneWidget);
      final cellText = tester.widget<Text>(find.text('3a'));
      expect(cellText.style?.color, Colors.red);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'flags a non-URL stored value in a URL field, not as a link',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

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
        final websiteFieldId = await fields.create(
          collectionId: collectionId,
          name: 'Website',
          type: FieldType.url,
        );
        final entryId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
          title: 'Buy milk',
        );
        // Only possible via a field type change (e.g. Text -> URL)
        // leaving old free-text values behind (see
        // FieldsRepository.changeType) - the grid must flag it rather
        // than render it as a clickable link.
        await pages.setPropertyValue(entryId, websiteFieldId, 'not a url');
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            CollectionView(
              collectionId: collectionId,
              onEdit: () {},
              onOpenEntry: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('not a url'), findsOneWidget);
      final cellText = tester.widget<Text>(find.text('not a url'));
      expect(cellText.style?.color, Colors.red);
      expect(cellText.style?.decoration, isNot(TextDecoration.underline));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'flags a non-date stored value in a date field instead of hiding it',
    (WidgetTester tester) async {
      final database = newTestDatabase();
      addTearDown(database.close);

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
        final dueFieldId = await fields.create(
          collectionId: collectionId,
          name: 'Due',
          type: FieldType.date,
        );
        final entryId = await pages.create(
          spaceId: spaceId,
          collectionId: collectionId,
          title: 'Buy milk',
        );
        await pages.setPropertyValue(entryId, dueFieldId, 'not a date');
      });

      await tester.pumpWidget(
        AppScope(
          database: database,
          child: wrapWithAppLocalizations(
            CollectionView(
              collectionId: collectionId,
              onEdit: () {},
              onOpenEntry: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('not a date'), findsOneWidget);
      final cellText = tester.widget<Text>(find.text('not a date'));
      expect(cellText.style?.color, Colors.red);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
