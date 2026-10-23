import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/files/data/attachments_repository.dart';
import 'package:turtle_base/features/files/widgets/attachment_thumbnail.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/pages/widgets/page_properties_header.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/packages/file_store/file_store.dart';

import '../../../support/pump_app.dart';

void main() {
  late Directory tmp;
  late FileStore files;
  late AppDatabase database;
  late String collectionId;
  late String fieldId;
  late String pageId;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('files_field_value_test');
    files = FileStore(p.join(tmp.path, 'files'));
    database = newTestDatabase();
  });

  tearDown(() async {
    await database.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> seed(WidgetTester tester, {String? config, int images = 1}) async {
    await tester.runAsync(() async {
      final spaceId = await SpacesRepository(database).create(name: 'Space');
      collectionId = await CollectionsRepository(database).create(spaceId: spaceId, name: 'Books');
      fieldId = await FieldsRepository(database)
          .create(collectionId: collectionId, name: 'Cover', type: BaseFieldType.files, config: config);
      pageId = await PagesRepository(database).create(spaceId: spaceId, collectionId: collectionId);
      for (var i = 0; i < images; i++) {
        final source = File(p.join(tmp.path, 'cover$i.png'))
          ..writeAsBytesSync(img.encodePng(img.Image(width: 4 + i, height: 4)));
        final stored = await files.import(source);
        await AttachmentsRepository(database).create(
          pageId: pageId,
          fieldId: fieldId,
          file: AttachmentFile(
            fileHash: stored.hash,
            name: 'cover$i.png',
            mimeType: stored.mimeType,
            size: stored.size,
            width: stored.width,
            height: stored.height,
          ),
        );
      }
    });
  }

  Future<void> pumpHeader(WidgetTester tester) async {
    await tester.pumpWidget(
      AppScope(
        database: database,
        files: files,
        child: wrapWithAppLocalizations(
          Scaffold(
            body: PagePropertiesHeader(pageId: pageId, collectionId: collectionId),
          ),
        ),
      ),
    );
    // Page, fields and attachments are nested streams, each needing a
    // round of real I/O before the next one is subscribed.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  testWidgets('shows a preview per attachment and an add button', (WidgetTester tester) async {
    await seed(tester, images: 2);
    await pumpHeader(tester);

    expect(find.text('Cover'), findsOneWidget);
    expect(find.byType(AttachmentThumbnail), findsNWidgets(2));
    expect(find.byTooltip('Add file'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a full single-file field has no add button', (WidgetTester tester) async {
    await seed(tester, config: '{"maxFiles": 1}');
    await pumpHeader(tester);

    expect(find.byType(AttachmentThumbnail), findsOneWidget);
    expect(find.byTooltip('Add file'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('removing an attachment soft-deletes it', (WidgetTester tester) async {
    await seed(tester);
    await pumpHeader(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    final stored = await tester.runAsync(() => database.select(database.attachments).get());
    expect(stored!.single.deletedAt, isNotNull);
    expect(find.byType(AttachmentThumbnail), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
