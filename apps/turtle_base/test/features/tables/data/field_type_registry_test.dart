import 'package:field_types/field_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/field_type_registry.dart';
import 'package:turtle_base/features/tables/data/field_variants.dart';
import 'package:turtle_base/features/tables/data/resolved_field.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';

Field fieldRow(String type, {String? config}) {
  final now = DateTime(2026);
  return Field(
    createdAt: now,
    updatedAt: now,
    createdBy: 'u',
    updatedBy: 'u',
    id: 'f',
    collectionId: 'c',
    name: 'Field',
    type: type,
    position: 0,
    config: config,
  );
}

Object? storedOf(ParsedInput parsed) => switch (parsed) {
  ParsedValue(:final stored) => stored,
  ParseError(:final message) => fail('Unexpected parse error: $message'),
};

void main() {
  final registry = FieldTypeRegistry();

  group('resolve', () {
    test('reads the variant from the config', () {
      final field = registry.resolve(fieldRow('text', config: '{"variant": "url"}'));
      expect(field.base, BaseFieldType.text);
      expect(field.variant, urlVariant);
      expect(field.typeLabel, 'URL');
    });

    test('maps the legacy url type to text with the url variant', () {
      final field = registry.resolve(fieldRow('url'));
      expect(field.base, BaseFieldType.text);
      expect(field.variant, urlVariant);
    });

    test('ignores a variant this device does not know', () {
      final field = registry.resolve(fieldRow('text', config: '{"variant": "books.isbn"}'));
      expect(field.base, BaseFieldType.text);
      expect(field.variant, isNull);
    });

    test('ignores a variant of another base type', () {
      final field = registry.resolve(fieldRow('number', config: '{"variant": "url"}'));
      expect(field.variant, isNull);
    });

    test('falls back to unsupported for an unknown base type', () {
      final field = registry.resolve(fieldRow('hologram'));
      expect(field.base, isA<UnsupportedFieldType>());
      expect(field.display({'x': 1}), '{x: 1}');
    });

    test('registers variants passed in', () {
      const variant = TextVariant(id: 'test.shout', label: 'Shout');
      final withVariant = FieldTypeRegistry(variants: [variant]);
      expect(withVariant.choices.map((c) => c.key), contains('test.shout'));
      expect(withVariant.resolve(fieldRow('text', config: '{"variant": "test.shout"}')).variant, variant);
    });
  });

  group('number', () {
    final field = registry.resolve(fieldRow('number'));

    test('reads numeric strings stored before numbers were JSON numbers', () {
      expect(field.valueOf('12.5'), 12.5);
      expect(field.errorFor('12.5'), isNull);
    });

    test('stores parsed input as a JSON number', () {
      expect(storedOf(field.parse('42')), 42);
    });

    test('flags and still shows a value that is not a number', () {
      expect(field.errorFor('3a'), isNotNull);
      expect(field.display('3a'), '3a');
    });

    test('shows whole doubles without a decimal part', () {
      expect(field.display(3.0), '3');
    });
  });

  group('text', () {
    final field = registry.resolve(fieldRow('text'));

    test('reads values of other literal types as text', () {
      expect(field.display(42), '42');
      expect(field.errorFor(42), isNull);
    });

    test('stores empty input as null', () {
      expect(storedOf(field.parse('  ')), isNull);
    });
  });

  group('url variant', () {
    final field = registry.resolve(fieldRow('text', config: '{"variant": "url"}'));

    test('rejects an invalid URL', () {
      expect(field.parse('not a url'), isA<ParseError>());
    });

    test('normalizes and links a valid one', () {
      expect(storedOf(field.parse(' example.com ')), 'example.com');
      expect(field.linkFor('example.com'), Uri.parse('https://example.com'));
    });

    test('does not link an invalid stored value', () {
      expect(field.linkFor('not a url'), isNull);
    });
  });

  group('date', () {
    final field = registry.resolve(fieldRow('date'));

    test('stores a plain date without a time', () {
      expect(storedOf(field.parse('2026-07-18')), '2026-07-18');
    });

    test('keeps the time of a timestamp', () {
      expect(field.errorFor('2026-07-18T10:30:00'), isNull);
      expect(field.display('2026-07-18T10:30:00'), '2026-07-18T10:30:00.000');
    });
  });

  group('select', () {
    const options = [
      SelectOption(id: 'o1', name: 'Red', color: OptionColor.red),
      SelectOption(id: 'o2', name: 'Blue', color: OptionColor.blue),
    ];
    final config = encodeSelectConfig(options);

    test('reads option names, as left behind by a field converted from text', () {
      final field = registry.resolve(fieldRow('select', config: config));
      expect(field.valueOf('red'), ['o1']);
      expect(field.display('red'), 'Red');
    });

    test('a multi-select splits comma-separated names', () {
      final field = registry.resolve(fieldRow('multiSelect', config: config));
      expect(field.valueOf('Red, Blue'), ['o1', 'o2']);
    });

    test('reads a single select id as a multi-select value and back', () {
      final multi = registry.resolve(fieldRow('multiSelect', config: config));
      final single = registry.resolve(fieldRow('select', config: config));
      expect(multi.valueOf('o2'), ['o2']);
      expect(single.base.encode(single.valueOf(['o2'])!, single.config), 'o2');
    });
  });
}
