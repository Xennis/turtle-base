import 'package:field_types/field_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextVariant.pattern', () {
    final variant = TextVariant.pattern(id: 'digits', label: 'Digits', pattern: RegExp(r'\d+'), message: 'Digits only');

    test('accepts a full match', () {
      expect(variant.validate('123'), isNull);
    });

    test('rejects a partial match', () {
      expect(variant.validate('123a'), 'Digits only');
      expect(variant.validate('a123'), 'Digits only');
    });
  });

  test('a variant without hooks passes values through', () {
    const variant = NumberVariant(id: 'plain', label: 'Plain');
    expect(variant.validate(3), isNull);
    expect(variant.normalize(3), 3);
    expect(variant.format(3), isNull);
    expect(variant.link(3), isNull);
  });

  test('hooks are callable through a FieldVariant<Object>', () {
    final FieldVariant<Object> variant = TextVariant(id: 'upper', label: 'Upper', normalize: (v) => v.toUpperCase());
    expect(variant.normalize('abc'), 'ABC');
  });
}
