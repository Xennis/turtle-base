import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/field_type_registry.dart';
import 'package:turtle_base/features/tables/data/field_variants.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/features/tables/data/relation_field.dart';
import 'package:turtle_base/features/tables/data/resolved_field.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';
import 'package:turtle_base/features/tables/widgets/collection_edit_page.dart';

import '../../../support/pump_app.dart';

void main() {
  testWidgets('Edit collection page: rename the collection, add, rename, retype, delete a field', (
    WidgetTester tester,
  ) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String collectionId;
    await tester.runAsync(() async {
      final spaceId = await SpacesRepository(database).create(name: 'Space');
      collectionId = await CollectionsRepository(database).create(spaceId: spaceId, name: 'Tasks');
    });

    await tester.pumpWidget(
      AppScope(
        database: database,
        child: wrapWithAppLocalizations(
          CollectionEditPage(collectionId: collectionId, onDone: () {}, onDeleted: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('No fields yet'), findsOneWidget);

    // Rename the collection via its own name field.
    await tester.enterText(find.widgetWithText(ShadInput, 'Tasks'), 'To-dos');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    var storedCollection = await database.select(database.collections).getSingle();
    expect(storedCollection.name, 'To-dos');

    // Add a field via the "new field" row, defaulting to text.
    await tester.enterText(find.byType(ShadInput).last, 'Priority');
    await tester.tap(find.widgetWithText(ShadButton, 'Add field'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    var storedFields = await database.select(database.fields).get();
    expect(storedFields.single.name, 'Priority');
    expect(storedFields.single.type, 'text');
    expect(find.textContaining('No fields yet'), findsNothing);

    // Rename it inline (the field row's TextField, identified by its
    // current value).
    await tester.enterText(find.widgetWithText(ShadInput, 'Priority'), 'Urgency');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    storedFields = await database.select(database.fields).get();
    expect(storedFields.single.name, 'Urgency');

    // Change its type via the row's dropdown (the field row's, not
    // the "new field" row's - it comes first in the list). The
    // Collection card's Icon row pushes it down, so ensure it's
    // scrolled into view before tapping.
    await tester.ensureVisible(find.byType(ShadSelect<FieldTypeChoice>).first);
    await tester.tap(find.byType(ShadSelect<FieldTypeChoice>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Number').last);
    await tester.pumpAndSettle();

    storedFields = await database.select(database.fields).get();
    expect(storedFields.single.type, 'number');

    // Delete it (not the collection's own delete button in the AppBar).
    await tester.tap(find.byTooltip('Delete field'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('No fields yet'), findsOneWidget);
    storedFields = await database.select(database.fields).get();
    expect(storedFields.single.deletedAt, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('Edit collection page: customize the Name column label', (WidgetTester tester) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String collectionId;
    await tester.runAsync(() async {
      final spaceId = await SpacesRepository(database).create(name: 'Space');
      collectionId = await CollectionsRepository(database).create(spaceId: spaceId, name: 'Tasks');
    });

    await tester.pumpWidget(
      AppScope(
        database: database,
        child: wrapWithAppLocalizations(
          CollectionEditPage(collectionId: collectionId, onDone: () {}, onDeleted: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Second TextField in the Collection card - the title-column
    // label, empty by default (shows "Name" only as a hint).
    await tester.enterText(find.byType(ShadInput).at(1), 'Task');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    var storedCollection = await database.select(database.collections).getSingle();
    expect(storedCollection.titleFieldLabel, 'Task');

    // Clearing it resets to the "Name" default rather than being
    // ignored (unlike the collection's own name field).
    await tester.enterText(find.byType(ShadInput).at(1), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    storedCollection = await database.select(database.collections).getSingle();
    expect(storedCollection.titleFieldLabel, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a relation field requires and stores a target collection', (WidgetTester tester) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String collectionId;
    late String targetCollectionId;
    await tester.runAsync(() async {
      final spaceId = await SpacesRepository(database).create(name: 'Space');
      final collections = CollectionsRepository(database);
      collectionId = await collections.create(spaceId: spaceId, name: 'Tasks');
      targetCollectionId = await collections.create(spaceId: spaceId, name: 'Projects');
    });

    await tester.pumpWidget(
      AppScope(
        database: database,
        child: wrapWithAppLocalizations(
          CollectionEditPage(collectionId: collectionId, onDone: () {}, onDeleted: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(find.byType(ShadInput).last, 'Project');
    await tester.tap(find.byType(ShadSelect<FieldTypeChoice>).last);
    await tester.pumpAndSettle();
    // Further down the type list than fits the popover.
    final relationOption = find.descendant(
      of: find.byType(ShadOption<FieldTypeChoice>),
      matching: find.text('Relation'),
    );
    await tester.ensureVisible(relationOption);
    await tester.pumpAndSettle();
    await tester.tap(relationOption);
    await tester.pumpAndSettle();

    // Blocked until a target collection is picked - a relation field
    // without one is useless.
    final addButton = tester.widget<ShadButton>(find.widgetWithText(ShadButton, 'Add field'));
    expect(addButton.onPressed, isNull);

    await tester.tap(find.byType(ShadSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ShadButton, 'Add field'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final storedFields = await database.select(database.fields).get();
    expect(storedFields.single.type, 'relation');
    expect(decodeRelationTargetCollectionId(storedFields.single.config), targetCollectionId);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a select field\'s options can be added, renamed, recolored and deleted', (WidgetTester tester) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String collectionId;
    late String fieldId;
    await tester.runAsync(() async {
      final spaceId = await SpacesRepository(database).create(name: 'Space');
      collectionId = await CollectionsRepository(database).create(spaceId: spaceId, name: 'Tasks');
      final fields = FieldsRepository(database);
      fieldId = await fields.create(
        collectionId: collectionId,
        name: 'Status',
        type: BaseFieldType.select,
        config: encodeSelectConfig(const []),
      );
      await fields.addSelectOption(fieldId, 'To do');
    });

    Future<List<SelectOption>> storedOptions() async {
      final field = await database.select(database.fields).getSingle();
      return decodeSelectOptions(field.config);
    }

    await tester.pumpWidget(
      AppScope(
        database: database,
        child: wrapWithAppLocalizations(
          CollectionEditPage(collectionId: collectionId, onDone: () {}, onDeleted: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Options live in the field's settings, folded away by default.
    await tester.tap(find.byTooltip('Field settings'));
    await tester.pumpAndSettle();

    // Add one via the field's own "Add option" input.
    final addOption = find.widgetWithText(ShadInput, 'Add option');
    await tester.ensureVisible(addOption);
    await tester.enterText(addOption, 'Done');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect((await storedOptions()).map((o) => o.name), ['To do', 'Done']);

    // Rename the first one inline.
    await tester.enterText(find.widgetWithText(ShadInput, 'To do'), 'Open');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    var options = await storedOptions();
    expect(options.first.name, 'Open');

    // Recolor it via the palette popover.
    await tester.tap(find.byTooltip('Change color').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Red'));
    await tester.pumpAndSettle();

    options = await storedOptions();
    expect(options.first.color, OptionColor.red);

    // Delete the second one, after confirming.
    await tester.tap(find.byTooltip('Delete option').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ShadButton, 'Delete'));
    await tester.pumpAndSettle();

    expect((await storedOptions()).map((o) => o.name), ['Open']);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a number field\'s min and max are stored in its config', (WidgetTester tester) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String collectionId;
    late String fieldId;
    await tester.runAsync(() async {
      final spaceId = await SpacesRepository(database).create(name: 'Space');
      collectionId = await CollectionsRepository(database).create(spaceId: spaceId, name: 'Books');
      fieldId = await FieldsRepository(database)
          .create(collectionId: collectionId, name: 'Rating', type: BaseFieldType.number);
    });

    await tester.pumpWidget(
      AppScope(
        database: database,
        child: wrapWithAppLocalizations(
          CollectionEditPage(collectionId: collectionId, onDone: () {}, onDeleted: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    Future<void> enter(String label, String value) async {
      final input = find.widgetWithText(ShadInputFormField, label);
      await tester.ensureVisible(input);
      await tester.enterText(find.descendant(of: input, matching: find.byType(EditableText)), value);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byTooltip('Field settings'));
    await tester.pumpAndSettle();

    await enter('Min', '1');
    await enter('Max', '5');
    // Rejected, so not stored.
    await enter('Max', 'five');

    final stored = await database.select(database.fields).getSingle();
    expect(stored.id, fieldId);
    expect(decodeFieldConfig(stored.config), {'min': 1, 'max': 5});
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('changing a type that rewrites values asks first, and cancelling keeps everything', (
    WidgetTester tester,
  ) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String collectionId;
    late String fieldId;
    late String entryId;
    late String optionId;
    await tester.runAsync(() async {
      final spaceId = await SpacesRepository(database).create(name: 'Space');
      collectionId = await CollectionsRepository(database).create(spaceId: spaceId, name: 'Books');
      final fields = FieldsRepository(database);
      fieldId = await fields.create(
        collectionId: collectionId,
        name: 'Status',
        type: BaseFieldType.select,
        config: encodeSelectConfig(const []),
      );
      optionId = (await fields.addSelectOption(fieldId, 'Reading')).id;
      entryId = await PagesRepository(database)
          .create(spaceId: spaceId, collectionId: collectionId, properties: {fieldId: optionId});
    });

    await tester.pumpWidget(
      AppScope(
        database: database,
        child: wrapWithAppLocalizations(
          CollectionEditPage(collectionId: collectionId, onDone: () {}, onDeleted: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The type change plans and writes through the database in a few
    // steps - each needs real async time and a pump to continue.
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> pickText() async {
      await tester.ensureVisible(find.byType(ShadSelect<FieldTypeChoice>).first);
      await tester.tap(find.byType(ShadSelect<FieldTypeChoice>).first);
      await tester.pumpAndSettle();
      // Not just find.text - the "new field" row's select shows Text too.
      await tester.tap(find.descendant(of: find.byType(ShadOption<FieldTypeChoice>), matching: find.text('Text')));
      await settle();
    }

    Future<Object?> storedValue() async {
      final entry = await (database.select(database.pages)..where((p) => p.id.equals(entryId))).getSingle();
      return decodePageProperties(entry.properties)[fieldId];
    }

    await pickText();
    expect(find.text('Change type to Text?'), findsOneWidget);
    expect(find.textContaining('1 value will be converted to Text'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect((await database.select(database.fields).getSingle()).type, 'select');
    expect(await storedValue(), optionId);

    await pickText();
    await tester.tap(find.text('Change type'));
    await settle();

    expect((await database.select(database.fields).getSingle()).type, 'text');
    expect(await storedValue(), 'Reading');
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('fields are reordered by dragging, and only plain types have settings', (WidgetTester tester) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String collectionId;
    await tester.runAsync(() async {
      final spaceId = await SpacesRepository(database).create(name: 'Space');
      collectionId = await CollectionsRepository(database).create(spaceId: spaceId, name: 'Books');
      final fields = FieldsRepository(database);
      await fields.create(collectionId: collectionId, name: 'Subtitle', type: BaseFieldType.text);
      await fields.create(collectionId: collectionId, name: 'Website', type: BaseFieldType.text, variant: urlVariant);
    });

    await tester.pumpWidget(
      AppScope(
        database: database,
        child: wrapWithAppLocalizations(
          CollectionEditPage(collectionId: collectionId, onDone: () {}, onDeleted: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // A URL validates itself - a pattern on top would clash with it.
    expect(find.byTooltip('Field settings').hitTestable(), findsOneWidget);

    final handle = find.byIcon(Icons.drag_indicator).first;
    await tester.ensureVisible(handle);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    final stored = await database.select(database.fields).get();
    stored.sort((a, b) => a.position.compareTo(b.position));
    expect(stored.map((f) => f.name), ['Website', 'Subtitle']);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
