import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/field_conversion.dart';
import 'package:turtle_base/features/tables/data/field_type_registry.dart';
import 'package:turtle_base/features/tables/data/field_variants.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/features/tables/data/relation_field.dart';
import 'package:turtle_base/features/tables/data/resolved_field.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';

import '../../../support/pump_app.dart';

void main() {
  late AppDatabase database;
  late FieldsRepository fields;
  late PagesRepository pages;
  late String spaceId;
  late String collectionId;

  setUp(() async {
    database = newTestDatabase();
    spaceId = await SpacesRepository(database).create(name: 'Space');
    collectionId = await CollectionsRepository(database).create(spaceId: spaceId, name: 'Books');
    fields = FieldsRepository(database);
    pages = PagesRepository(database);
  });

  tearDown(() => database.close());

  Future<Map<String, Object?>> configOf(String fieldId) async =>
      decodeFieldConfig((await fields.watchById(fieldId).first).config);

  Future<String> entryWith(String fieldId, Object? value, {String title = ''}) =>
      pages.create(spaceId: spaceId, collectionId: collectionId, title: title, properties: {fieldId: value});

  Future<Object?> valueOf(String pageId, String fieldId) async =>
      decodePageProperties((await pages.watchById(pageId).first).properties)[fieldId];

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

  group('type conversion', () {
    test('text to number keeps the values and previews the ones that do not fit', () async {
      final id = await fields.create(collectionId: collectionId, name: 'Pages', type: BaseFieldType.text);
      final fits = await entryWith(id, '320');
      await entryWith(id, 'about 300');
      await entryWith(id, '');

      final plan = await fields.planTypeChange(id, const FieldTypeChoice(BaseFieldType.number));
      expect(plan.mode, ConversionMode.lazy);
      expect(plan.valueCount, 2);
      expect(plan.invalidCount, 1);
      expect(plan.invalidSamples, ['about 300']);

      await fields.applyTypeChange(plan);
      expect((await fields.watchById(id).first).type, 'number');
      expect(await valueOf(fits, id), '320');
    });

    test('text to multi-select creates an option per distinct name', () async {
      final id = await fields.create(collectionId: collectionId, name: 'Genres', type: BaseFieldType.text);
      final entry = await entryWith(id, 'Fantasy, Sci-Fi');
      await entryWith(id, 'fantasy');

      await fields.changeType(id, const FieldTypeChoice(BaseFieldType.multiSelect));

      final field = FieldTypeRegistry().resolve(await fields.watchById(id).first);
      expect((field.config as SelectConfig).options.map((o) => o.name), ['Fantasy', 'Sci-Fi']);
      expect(field.display(await valueOf(entry, id)), 'Fantasy, Sci-Fi');
    });

    test('select to text rewrites option ids as names', () async {
      final id = await fields.create(
        collectionId: collectionId,
        name: 'Status',
        type: BaseFieldType.select,
        config: encodeSelectConfig(const []),
      );
      final option = await fields.addSelectOption(id, 'Reading');
      final entry = await entryWith(id, option.id);

      final plan = await fields.planTypeChange(id, const FieldTypeChoice(BaseFieldType.text));
      expect(plan.mode, ConversionMode.rewrite);

      await fields.applyTypeChange(plan);
      expect(await valueOf(entry, id), 'Reading');
    });

    test('relation to text rewrites page ids as titles', () async {
      final authors = await CollectionsRepository(database).create(spaceId: spaceId, name: 'Authors');
      final author = await pages.create(spaceId: spaceId, collectionId: authors, title: 'Ursula K. Le Guin');
      final id = await fields.create(
        collectionId: collectionId,
        name: 'Author',
        type: BaseFieldType.relation,
        config: encodeRelationConfig(authors),
      );
      final entry = await entryWith(id, [author]);

      await fields.changeType(id, const FieldTypeChoice(BaseFieldType.text));
      expect(await valueOf(entry, id), 'Ursula K. Le Guin');
    });

    test('a conversion that is not offered changes nothing', () async {
      final id = await fields.create(collectionId: collectionId, name: 'Pages', type: BaseFieldType.number);

      await fields.changeType(id, const FieldTypeChoice(BaseFieldType.relation));
      expect((await fields.watchById(id).first).type, 'number');
    });
  });

  test('conversionMode', () {
    expect(conversionMode(BaseFieldType.text, BaseFieldType.number), ConversionMode.lazy);
    expect(conversionMode(BaseFieldType.select, BaseFieldType.multiSelect), ConversionMode.lazy);
    expect(conversionMode(BaseFieldType.select, BaseFieldType.number), ConversionMode.rewrite);
    expect(conversionMode(BaseFieldType.relation, BaseFieldType.text), ConversionMode.rewrite);
    expect(conversionMode(BaseFieldType.relation, BaseFieldType.number), ConversionMode.none);
    expect(conversionMode(BaseFieldType.text, BaseFieldType.relation), ConversionMode.none);
    expect(conversionMode(const UnsupportedFieldType('x'), BaseFieldType.text), ConversionMode.none);
  });

  test('reorderAll gives the fields the given order', () async {
    final a = await fields.create(collectionId: collectionId, name: 'A', type: BaseFieldType.text);
    final b = await fields.create(collectionId: collectionId, name: 'B', type: BaseFieldType.text);
    final c = await fields.create(collectionId: collectionId, name: 'C', type: BaseFieldType.text);

    await fields.reorderAll([c, a, b]);

    final ordered = await fields.watchAllInCollection(collectionId).first;
    expect(ordered.map((f) => f.name), ['C', 'A', 'B']);
  });
}
