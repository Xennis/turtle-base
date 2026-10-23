import 'dart:io';

import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/plugins/data/plugin_instances_repository.dart';
import 'package:turtle_base/features/plugins/data/plugin_registry.dart';
import 'package:turtle_base/features/plugins/widgets/entry_lookup_dialog.dart';
import 'package:turtle_base/packages/file_store/file_store.dart';
import 'package:turtle_plugin/turtle_plugin.dart';

import '../../../support/pump_app.dart';

class _FakeLookup implements EntryLookup {
  final queries = <String>[];
  LookupException? error;

  @override
  String get actionLabel => 'Add item';
  @override
  String get searchHint => 'Name or code';
  @override
  String? get uniqueFieldKey => 'code';

  @override
  Future<List<EntryDraft>> search(String query) async {
    queries.add(query);
    if (error case final error?) throw error;
    return [
      EntryDraft(title: '$query one', subtitle: 'First', values: {'code': '${query}1'}),
      EntryDraft(title: '$query two', values: {'code': '${query}2'}),
    ];
  }
}

const _plugin = TurtlePlugin(
  id: 'demo',
  name: 'Demo',
  description: '',
  collections: [
    CollectionTemplate(key: 'items', name: 'Items', fields: [TextFieldTemplate('code', 'Code')]),
  ],
);

void main() {
  late AppDatabase database;
  late String collectionId;
  late _FakeLookup lookup;
  String? opened;

  setUp(() {
    database = newTestDatabase();
    lookup = _FakeLookup();
    opened = null;
  });

  tearDown(() => database.close());

  Future<void> settle(WidgetTester tester) async {
    // Each round lets one more database round trip finish.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  Future<void> pumpAndOpen(WidgetTester tester) async {
    final spaceId = await tester.runAsync(() => PluginInstancesRepository(database).add(_plugin));
    collectionId = pluginCollectionId(spaceId!, 'items');
    await tester.pumpWidget(
      AppScope(
        database: database,
        files: FileStore(Directory.systemTemp.path),
        child: wrapWithAppLocalizations(
          Scaffold(
            body: Builder(
              builder: (context) => ShadButton(
                onPressed: () => showEntryLookup(
                  context,
                  collectionId: collectionId,
                  lookup: lookup,
                  onOpenEntry: (id) => opened = id,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(EditableText), query);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  Future<List<Page>> entries(WidgetTester tester) async =>
      (await tester.runAsync(() => PagesRepository(database).watchAllInCollection(collectionId).first))!;

  testWidgets('adds the picked result and opens it', (WidgetTester tester) async {
    await pumpAndOpen(tester);
    expect(find.text('Add item'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'du');
    await tester.pump(const Duration(milliseconds: 100));
    await search(tester, 'dune');
    // Debounced: only the last input was searched.
    expect(lookup.queries, ['dune']);
    expect(find.text('dune one'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);

    await tester.tap(find.text('dune two'));
    await settle(tester);

    final entry = (await entries(tester)).single;
    expect(entry.title, 'dune two');
    expect(opened, entry.id);
    await tester.pumpAndSettle();
    expect(find.text('Add item'), findsNothing);
  });

  testWidgets('opens an entry already in the collection instead of adding a copy', (WidgetTester tester) async {
    await pumpAndOpen(tester);
    final existing = await tester.runAsync(
      () => PagesRepository(database).create(
        spaceId: collectionId.substring(0, collectionId.lastIndexOf('.')),
        collectionId: collectionId,
        title: 'Mine',
        properties: {pluginFieldId(collectionId, 'code'): 'dune1'},
      ),
    );

    await search(tester, 'dune');
    await tester.tap(find.text('dune one'));
    await settle(tester);

    expect((await entries(tester)).map((e) => e.id), [existing]);
    expect(opened, existing);
  });

  testWidgets('shows a failed search and still allows adding by hand', (WidgetTester tester) async {
    lookup.error = const LookupException("Couldn't reach the source");
    await pumpAndOpen(tester);

    await search(tester, 'dune');
    expect(find.text("Couldn't reach the source"), findsOneWidget);

    await tester.tap(find.text('Add "dune" manually'));
    await settle(tester);

    expect((await entries(tester)).single.title, 'dune');
    expect(opened, isNotNull);
  });
}
