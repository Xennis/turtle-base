import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/features/tables/data/relation_field.dart';

void main() {
  test('encodes and decodes the target collection id', () {
    final config = encodeRelationConfig('collection_1');
    expect(decodeRelationTargetCollectionId(config), 'collection_1');
  });

  test('decodeRelationTargetCollectionId returns null for null config', () {
    expect(decodeRelationTargetCollectionId(null), isNull);
  });

  test('decodeRelationValue reads a list of page ids', () {
    expect(decodeRelationValue(['page_1', 'page_2']), ['page_1', 'page_2']);
  });

  test('decodeRelationValue treats anything else as empty', () {
    expect(decodeRelationValue(null), isEmpty);
    expect(decodeRelationValue('not a list'), isEmpty);
  });
}
