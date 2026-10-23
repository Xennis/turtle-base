import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/files/data/attachments_repository.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';

import '../../../support/pump_app.dart';

AttachmentFile _file(String hash, {String mimeType = 'image/png'}) =>
    AttachmentFile(fileHash: hash, name: '$hash.png', mimeType: mimeType, size: 3);

void main() {
  late AppDatabase database;
  late AttachmentsRepository attachments;
  late String spaceId;
  late String collectionId;
  late String fieldId;
  late String pageId;

  setUp(() async {
    database = newTestDatabase();
    spaceId = await SpacesRepository(database).create(name: 'Space');
    collectionId = await CollectionsRepository(database).create(spaceId: spaceId, name: 'Books');
    fieldId = await FieldsRepository(database)
        .create(collectionId: collectionId, name: 'Cover', type: BaseFieldType.text);
    pageId = await PagesRepository(database).create(spaceId: spaceId, collectionId: collectionId);
    attachments = AttachmentsRepository(database);
  });

  tearDown(() => database.close());

  test('watchInField() lists a field\'s attachments in order, without deleted ones', () async {
    final a = await attachments.create(pageId: pageId, fieldId: fieldId, file: _file('a'));
    final b = await attachments.create(pageId: pageId, fieldId: fieldId, file: _file('b'));
    final c = await attachments.create(pageId: pageId, fieldId: fieldId, file: _file('c'));
    await attachments.create(pageId: pageId, file: _file('in-content'));
    await attachments.softDelete(b);

    final listed = await attachments.watchInField(pageId, fieldId).first;

    expect(listed.map((x) => x.id), [a, c]);
  });

  test('reorderAll() changes the order', () async {
    final a = await attachments.create(pageId: pageId, fieldId: fieldId, file: _file('a'));
    final b = await attachments.create(pageId: pageId, fieldId: fieldId, file: _file('b'));

    await attachments.reorderAll([b, a]);

    expect((await attachments.watchInField(pageId, fieldId).first).map((x) => x.id), [b, a]);
  });

  test('restore() brings a deleted attachment back', () async {
    final a = await attachments.create(pageId: pageId, fieldId: fieldId, file: _file('a'));
    await attachments.softDelete(a);

    await attachments.restore(a);

    expect(await attachments.watchInField(pageId, fieldId).first, hasLength(1));
  });

  test('fileHashes() includes deleted attachments only when asked to', () async {
    await attachments.create(pageId: pageId, fieldId: fieldId, file: _file('a'));
    final b = await attachments.create(pageId: pageId, fieldId: fieldId, file: _file('b'));
    await attachments.create(pageId: pageId, file: _file('a'));
    await attachments.softDelete(b);

    expect(await attachments.fileHashes(activeOnly: true), {'a'});
    expect(await attachments.fileHashes(activeOnly: false), {'a', 'b'});
  });

  test('watchInFieldOfCollection() groups by page', () async {
    final a = await attachments.create(pageId: pageId, fieldId: fieldId, file: _file('a'));

    final byPage = await attachments.watchInFieldOfCollection(collectionId, fieldId).first;

    expect(byPage.keys, [pageId]);
    expect(byPage[pageId]!.single.id, a);
  });

  test('copyTo() makes a new attachment of the same file', () async {
    final source = await attachments.byId(await attachments.create(pageId: pageId, file: _file('a')));
    final otherPage = await PagesRepository(database).create(spaceId: spaceId);

    final copyId = await attachments.copyTo(source!, pageId: otherPage);

    final copy = await attachments.byId(copyId);
    expect(copy!.pageId, otherPage);
    expect(copy.fileHash, 'a');
    expect(copy.isImage, isTrue);
  });
}
