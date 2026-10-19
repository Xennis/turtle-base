import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/features/spaces/data/spaces_repository.dart';
import 'package:turtle_base/features/tables/data/collections_repository.dart';
import 'package:turtle_base/features/tables/data/field_type.dart';
import 'package:turtle_base/features/tables/data/fields_repository.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';

import '../../../support/pump_app.dart';

void main() {
  const todo = SelectOption(id: 'o1', name: 'To do', color: OptionColor.gray);
  const done = SelectOption(id: 'o2', name: 'Done', color: OptionColor.green);

  test('encodes and decodes options in order', () {
    final config = encodeSelectConfig([todo, done]);
    expect(decodeSelectOptions(config), [todo, done]);
  });

  test('decodeSelectOptions returns empty for null or option-less config', () {
    expect(decodeSelectOptions(null), isEmpty);
    expect(decodeSelectOptions('{"targetCollectionId": "c1"}'), isEmpty);
  });

  test('an unknown stored color falls back to gray', () {
    final options = decodeSelectOptions(
      '{"options": [{"id": "o1", "name": "A", "color": "teal"}]}',
    );
    expect(options.single.color, OptionColor.gray);
  });

  test('decodeSelectValue accepts both a single id and a list', () {
    expect(decodeSelectValue('o1'), ['o1']);
    expect(decodeSelectValue(['o1', 'o2']), ['o1', 'o2']);
    expect(decodeSelectValue(''), isEmpty);
    expect(decodeSelectValue(null), isEmpty);
    expect(decodeSelectValue(42), isEmpty);
  });

  test('resolveSelectValue skips ids of deleted options', () {
    expect(resolveSelectValue([todo, done], ['o2', 'gone', 'o1']), [done, todo]);
  });

  test('encodeSelectValue stores a single id or a list', () {
    expect(encodeSelectValue(['o1'], multiple: false), 'o1');
    expect(encodeSelectValue([], multiple: false), isNull);
    expect(encodeSelectValue(['o1', 'o2'], multiple: true), ['o1', 'o2']);
  });

  test('nextOptionColor rotates through the palette', () {
    expect(nextOptionColor([]), OptionColor.values.first);
    expect(nextOptionColor([todo]), OptionColor.values[1]);
    expect(
      nextOptionColor(List.filled(OptionColor.values.length, todo)),
      OptionColor.values.first,
    );
  });

  test('FieldsRepository adds, updates and removes options', () async {
    final database = newTestDatabase();
    addTearDown(database.close);
    final spaceId = await SpacesRepository(database).create(name: 'Space');
    final collectionId = await CollectionsRepository(
      database,
    ).create(spaceId: spaceId, name: 'Tasks');
    final fields = FieldsRepository(database);
    final fieldId = await fields.create(
      collectionId: collectionId,
      name: 'Status',
      type: FieldType.select,
      config: encodeSelectConfig(const []),
    );

    final first = await fields.addSelectOption(fieldId, 'To do');
    final second = await fields.addSelectOption(fieldId, 'Done');
    expect(first.color, OptionColor.values[0]);
    expect(second.color, OptionColor.values[1]);

    await fields.updateSelectOption(
      fieldId,
      first.copyWith(name: 'Open', color: OptionColor.red),
    );
    await fields.removeSelectOption(fieldId, second.id);

    final field = await fields.watchById(fieldId).first;
    final options = decodeSelectOptions(field.config);
    expect(options.single.id, first.id);
    expect(options.single.name, 'Open');
    expect(options.single.color, OptionColor.red);
  });
}
