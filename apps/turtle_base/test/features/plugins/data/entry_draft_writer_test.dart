import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/files/data/attachments_repository.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/plugins/data/entry_draft_writer.dart';
import 'package:turtle_base/features/plugins/data/plugin_instances_repository.dart';
import 'package:turtle_base/features/plugins/data/plugin_registry.dart';
import 'package:turtle_base/features/tables/data/field_type_registry.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/packages/file_store/file_store.dart';
import 'package:turtle_plugin/turtle_plugin.dart';

import '../../../support/pump_app.dart';

final _code = TextVariant(id: 'demo.code', label: 'Code', normalize: (v) => v.toUpperCase());

final _plugin = TurtlePlugin(
  id: 'demo',
  name: 'Demo',
  description: '',
  variants: [_code],
  collections: [
    CollectionTemplate(
      key: 'items',
      name: 'Items',
      fields: [
        const SelectFieldTemplate('status', 'Status', options: [OptionTemplate('open', 'Open', OptionColor.gray)]),
        TextFieldTemplate('code', 'Code', variant: _code),
        const NumberFieldTemplate('rating', 'Rating', min: 1, max: 5),
        const FilesFieldTemplate('cover', 'Cover', accept: ['image/*'], maxFiles: 1),
      ],
    ),
  ],
);

final _png = img.encodePng(img.Image(width: 2, height: 3));

void main() {
  late AppDatabase database;
  late Directory filesDir;
  late String collectionId;
  late List<Uri> downloaded;
  late EntryDraftWriter writer;
  final fieldTypes = FieldTypeRegistry(variants: PluginRegistry([_plugin]).variants);

  setUp(() async {
    database = newTestDatabase();
    filesDir = await Directory.systemTemp.createTemp('entry_draft_writer_test');
    final spaceId = await PluginInstancesRepository(database).add(_plugin);
    collectionId = pluginCollectionId(spaceId, 'items');
    downloaded = [];
    writer = EntryDraftWriter(
      database,
      fieldTypes: fieldTypes,
      files: FileStore(filesDir.path),
      client: MockClient((request) async {
        downloaded.add(request.url);
        return switch (request.url.path) {
          '/cover.png' => http.Response.bytes(_png, 200),
          '/notes.txt' => http.Response('plain text', 200),
          _ => http.Response('not found', 404),
        };
      }),
    );
  });

  tearDown(() async {
    await database.close();
    await filesDir.delete(recursive: true);
  });

  String fieldId(String key) => pluginFieldId(collectionId, key);

  Future<Page> entry(String id) => PagesRepository(database).watchById(id).first;

  test('stores the values that fit their field', () async {
    final id = await writer.create(
      collectionId,
      const EntryDraft(title: 'Dune', values: {'status': 'open', 'code': 'ab-1', 'rating': 9, 'unknown': 'x'}),
    );

    final page = await entry(id);
    expect(page.title, 'Dune');
    expect(decodePageProperties(page.properties), {fieldId('status'): 'open', fieldId('code'): 'AB-1'});
  });

  test('drops values of fields the user deleted', () async {
    await FieldsRepository(database).softDelete(fieldId('code'));

    final id = await writer.create(collectionId, const EntryDraft(title: 'Dune', values: {'code': 'ab-1'}));

    expect(decodePageProperties((await entry(id)).properties), isEmpty);
  });

  test('finds an entry with the same unique value', () async {
    const draft = EntryDraft(title: 'Dune', values: {'code': 'ab-1'});
    expect(await writer.findExisting(collectionId, draft, uniqueFieldKey: 'code'), isNull);

    final id = await writer.create(collectionId, draft);

    expect(await writer.findExisting(collectionId, draft, uniqueFieldKey: 'code'), id);
    expect(await writer.findExisting(collectionId, draft, uniqueFieldKey: null), isNull);
    expect(
      await writer.findExisting(
        collectionId,
        const EntryDraft(title: 'Dune', values: {'code': 'ab-2'}),
        uniqueFieldKey: 'code',
      ),
      isNull,
    );
  });

  test('attaches downloaded files the field takes, up to its maximum', () async {
    final draft = EntryDraft(
      title: 'Dune',
      files: {
        'cover': [
          Uri.parse('https://example.com/missing.png'),
          Uri.parse('https://example.com/notes.txt'),
          Uri.parse('https://example.com/cover.png'),
          Uri.parse('https://example.com/second.png'),
        ],
      },
    );
    final id = await writer.create(collectionId, draft);

    await writer.attachFiles(collectionId, id, draft);

    final attachments = await AttachmentsRepository(database).watchInField(id, fieldId('cover')).first;
    final cover = attachments.single;
    expect((cover.name, cover.mimeType, cover.width, cover.height), ('cover.png', 'image/png', 2, 3));
    // Stops once the field is full.
    expect(downloaded.map((u) => u.path), ['/missing.png', '/notes.txt', '/cover.png']);
  });
}
