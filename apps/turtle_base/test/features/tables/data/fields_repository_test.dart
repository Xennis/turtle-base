import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/field_type_registry.dart';
import 'package:turtle_base/features/tables/data/field_variants.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/features/tables/data/resolved_field.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';

import '../../../support/pump_app.dart';

void main() {
  late AppDatabase database;
  late FieldsRepository fields;
  late String collectionId;

  setUp(() async {
    database = newTestDatabase();
    final spaceId = await SpacesRepository(database).create(name: 'Space');
    collectionId = await CollectionsRepository(database).create(spaceId: spaceId, name: 'Books');
    fields = FieldsRepository(database);
  });

  tearDown(() => database.close());

  Future<Map<String, Object?>> configOf(String fieldId) async =>
      decodeFieldConfig((await fields.watchById(fieldId).first).config);

  test('create stores the variant and applies its preset', () async {
    final id = await fields.create(
      collectionId: collectionId,
      name: 'Rating',
      type: BaseFieldType.number,
      variant: ratingVariant,
    );
    expect(await configOf(id), {'min': 1, 'max': 5, 'decimals': 0, 'variant': 'rating'});
  });

  test('changeType keeps the config, so select options survive a round trip', () async {
    final id = await fields.create(
      collectionId: collectionId,
      name: 'Tags',
      type: BaseFieldType.select,
      config: encodeSelectConfig(const []),
    );
    final option = await fields.addSelectOption(id, 'Fiction');

    await fields.changeType(id, const FieldTypeChoice(BaseFieldType.multiSelect));
    await fields.changeType(id, const FieldTypeChoice(BaseFieldType.select));

    final field = await fields.watchById(id).first;
    expect(field.type, 'select');
    expect(decodeSelectOptions(field.config).single.id, option.id);
  });

  test('changeType sets and removes the variant', () async {
    final id = await fields.create(collectionId: collectionId, name: 'Link', type: BaseFieldType.text);

    await fields.changeType(id, FieldTypeChoice(BaseFieldType.text, urlVariant));
    expect((await configOf(id))[fieldVariantKey], 'url');

    await fields.changeType(id, const FieldTypeChoice(BaseFieldType.text));
    expect((await configOf(id)).containsKey(fieldVariantKey), isFalse);
  });

  test('config updates keep the variant', () async {
    final id = await fields.create(
      collectionId: collectionId,
      name: 'Link',
      type: BaseFieldType.text,
      variant: urlVariant,
    );

    await fields.updateConfig(id, '{"pattern": "x"}');
    expect(await configOf(id), {'pattern': 'x', 'variant': 'url'});

    await fields.updateConfigValues(id, {'pattern': null});
    expect(await configOf(id), {'variant': 'url'});
  });
}
