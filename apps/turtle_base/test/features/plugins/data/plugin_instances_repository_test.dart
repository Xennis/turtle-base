import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/files/data/file_accept.dart';
import 'package:turtle_base/features/plugins/data/plugin_instances_repository.dart';
import 'package:turtle_base/features/plugins/data/plugin_registry.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/field_type_registry.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';
import 'package:turtle_plugin/turtle_plugin.dart';

import '../../../support/pump_app.dart';

final _code = TextVariant(id: 'demo.code', label: 'Code');

final _plugin = TurtlePlugin(
  id: 'demo',
  name: 'Demo',
  description: 'A demo plugin',
  icon: '🧪',
  variants: [_code],
  collections: [
    CollectionTemplate(
      key: 'items',
      name: 'Items',
      icon: '📦',
      titleLabel: 'Item',
      fields: [
        const SelectFieldTemplate(
          'status',
          'Status',
          options: [
            OptionTemplate('open', 'Open', OptionColor.gray),
            OptionTemplate('done', 'Done', OptionColor.green),
          ],
        ),
        TextFieldTemplate('code', 'Code', variant: _code),
        const NumberFieldTemplate('rating', 'Rating', min: 1, max: 5),
        const DateFieldTemplate('due', 'Due'),
        const FilesFieldTemplate('cover', 'Cover', accept: ['image/*'], maxFiles: 1),
      ],
    ),
  ],
);

void main() {
  late AppDatabase database;
  late PluginInstancesRepository instances;
  final fieldTypes = FieldTypeRegistry(variants: PluginRegistry([_plugin]).variants);

  setUp(() {
    database = newTestDatabase();
    instances = PluginInstancesRepository(database);
  });

  tearDown(() => database.close());

  test('adds a space with the collections and fields of the templates', () async {
    final spaceId = await instances.add(_plugin);

    expect(isPluginSpaceId(spaceId, 'demo'), isTrue);
    final space = (await SpacesRepository(database).watchAll().first).single;
    expect((space.id, space.name, space.icon), (spaceId, 'Demo', '🧪'));

    final collectionId = pluginCollectionId(spaceId, 'items');
    final collection = await CollectionsRepository(database).watchById(collectionId).first;
    expect((collection.spaceId, collection.name, collection.icon), (spaceId, 'Items', '📦'));
    expect(collection.titleFieldLabel, 'Item');

    final fields = [
      for (final row in await FieldsRepository(database).watchAllInCollection(collectionId).first)
        fieldTypes.resolve(row),
    ];
    expect(fields.map((f) => f.id), [
      for (final key in ['status', 'code', 'rating', 'due', 'cover']) pluginFieldId(collectionId, key),
    ]);
    expect(fields.map((f) => f.name), ['Status', 'Code', 'Rating', 'Due', 'Cover']);

    final [status, code, rating, due, cover] = fields;
    expect(status.base, BaseFieldType.select);
    expect((status.config! as SelectConfig).options, const [
      SelectOption(id: 'open', name: 'Open', color: OptionColor.gray),
      SelectOption(id: 'done', name: 'Done', color: OptionColor.green),
    ]);
    expect((code.base, code.variant), (BaseFieldType.text, _code));
    expect(rating.base, BaseFieldType.number);
    expect(((rating.config! as NumberConfig).min, (rating.config! as NumberConfig).max), (1, 5));
    expect(due.base, BaseFieldType.date);
    expect(cover.base, BaseFieldType.files);
    expect((cover.config! as FilesConfig).accept, FileAccept.images);
    expect((cover.config! as FilesConfig).maxFiles, 1);
  });

  test('adding twice creates a second instance', () async {
    final first = await instances.add(_plugin);
    final second = await instances.add(_plugin);
    await SpacesRepository(database).create(name: 'Own space');

    expect(first, isNot(second));
    expect((await instances.watchInstances('demo').first).map((s) => s.id), [first, second]);
    expect(await instances.watchInstances('other').first, isEmpty);
  });
}
