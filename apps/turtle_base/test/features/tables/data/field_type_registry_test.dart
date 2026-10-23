import 'package:books/books.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/tables/data/base_field_type.dart';
import 'package:turtle_base/features/tables/data/field_type_registry.dart';
import 'package:turtle_base/features/tables/data/resolved_field.dart';
import 'package:turtle_base/features/tables/data/select_field.dart';
import 'package:turtle_plugin/turtle_plugin.dart';

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

    test('applies the books package\'s ISBN variant', () {
      final field = FieldTypeRegistry(variants: booksVariants)
          .resolve(fieldRow('text', config: '{"variant": "books.isbn"}'));
      expect(storedOf(field.parse('978-3-453-31717-8')), '9783453317178');
      expect(field.display('9783453317178'), '978-3453317178');
      expect(field.parse('978-3-453-31717-9'), isA<ParseError>());
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

  group('number config', () {
    final field = registry.resolve(fieldRow('number', config: '{"min": 0, "max": 10}'));

    test('rejects values outside min/max', () {
      expect((field.parse('11') as ParseError).message, 'Enter a number from 0 to 10');
      expect(field.parse('-1'), isA<ParseError>());
      expect(storedOf(field.parse('10')), 10);
    });

    test('flags stored values outside min/max', () {
      expect(field.errorFor(12), isNotNull);
    });
  });

  group('text config', () {
    test('requires a full match of the pattern', () {
      final field = registry.resolve(fieldRow('text', config: r'{"pattern": "[A-Z]{3}"}'));
      expect(storedOf(field.parse('ABC')), 'ABC');
      expect(field.parse('ABCD'), isA<ParseError>());
    });

    test('ignores a pattern that does not compile', () {
      final field = registry.resolve(fieldRow('text', config: '{"pattern": "("}'));
      expect(storedOf(field.parse('anything')), 'anything');
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

  group('email and phone variants', () {
    test('email validates and links via mailto', () {
      final field = registry.resolve(fieldRow('text', config: '{"variant": "email"}'));
      expect(field.parse('me@'), isA<ParseError>());
      expect(field.linkFor('me@example.com'), Uri.parse('mailto:me@example.com'));
    });

    test('phone links its digits via tel', () {
      final field = registry.resolve(fieldRow('text', config: '{"variant": "phone"}'));
      expect(field.parse('call me'), isA<ParseError>());
      expect(field.linkFor('+49 (30) 123-4567'), Uri.parse('tel:+49301234567'));
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

  group('checkbox', () {
    final field = registry.resolve(fieldRow('checkbox'));

    test('reads booleans, numbers and yes/no text', () {
      expect(field.valueOf(true), isTrue);
      expect(field.valueOf(0), isFalse);
      expect(field.valueOf('Yes'), isTrue);
      expect(field.errorFor('maybe'), isNotNull);
    });

    test('is read as 1/0 by a number field', () {
      expect(registry.resolve(fieldRow('number')).valueOf(true), 1);
    });
  });

  group('location', () {
    final field = registry.resolve(fieldRow('location'));

    test('parses "lat, lng" into an object', () {
      expect(storedOf(field.parse('52.52, 13.405')), {'lat': 52.52, 'lng': 13.405});
      expect(storedOf(field.parse('geo:-33.86;151.2')), {'lat': -33.86, 'lng': 151.2});
    });

    test('rejects text and out-of-range coordinates', () {
      expect(field.parse('Berlin'), isA<ParseError>());
      expect(field.parse('91, 0'), isA<ParseError>());
    });

    test('displays and links a stored position', () {
      const raw = {'lat': 52.52, 'lng': 13.405};
      expect(field.display(raw), '52.52, 13.405');
      expect(field.linkFor(raw)?.host, 'www.openstreetmap.org');
    });

    test('is read as "lat, lng" by a text field', () {
      expect(registry.resolve(fieldRow('text')).display({'lat': 52.52, 'lng': 13.405}), '52.52, 13.405');
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
