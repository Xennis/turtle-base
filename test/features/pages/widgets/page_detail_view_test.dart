import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/data/blocks_repository.dart';
import 'package:turtle_base/features/pages/widgets/page_detail_view.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';

import '../../../support/pump_app.dart';

void main() {
  testWidgets('shows the page title and its blocks', (
    WidgetTester tester,
  ) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String pageId;
    await tester.runAsync(() async {
      final spaceId = (await SpacesRepository(database).watchAll().first).single.id;
      // Reuse the same repository the app uses to create the page, so
      // the title/space wiring matches; the AppDatabase is shared.
      final pagesTable = database.pages;
      final now = DateTime.now();
      pageId = 'page_1';
      await database.into(pagesTable).insert(
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
      AppScope(database: database, child: wrapWithAppLocalizations(PageDetailView(pageId: pageId))),
    );
    await tester.pumpAndSettle();

    expect(find.text('My notes'), findsOneWidget);
    // find.textContaining doesn't match here - AppFlowyEditor renders
    // the paragraph as a RichText whose text is a TextSpan tree, and
    // toPlainText() (used below) walks it correctly where the finder's
    // own matching apparently doesn't. Confirmed by inspecting the
    // widget tree directly during development.
    final hasHelloWorld = tester
        .widgetList<RichText>(find.byType(RichText))
        .any((richText) => richText.text.toPlainText().contains('Hello world'));
    expect(hasHelloWorld, isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('renders an empty page without crashing', (
    WidgetTester tester,
  ) async {
    final database = newTestDatabase();
    addTearDown(database.close);

    late String pageId;
    await tester.runAsync(() async {
      final spaceId = (await SpacesRepository(database).watchAll().first).single.id;
      final now = DateTime.now();
      pageId = 'page_1';
      await database.into(database.pages).insert(
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
      AppScope(database: database, child: wrapWithAppLocalizations(PageDetailView(pageId: pageId))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Untitled'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
