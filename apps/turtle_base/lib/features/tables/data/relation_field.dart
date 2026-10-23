import 'dart:convert';

/// Encodes a relation field's `fields.config` - the only thing it
/// needs to store is which collection it points to (see
/// ARCHITECTURE.md's Feldtypen table; cardinality isn't picked in the
/// v1 Field-Editor UI, see UI_UX.md, so it's not stored either).
String encodeRelationConfig(String targetCollectionId) {
  return jsonEncode({'targetCollectionId': targetCollectionId});
}

String? decodeRelationTargetCollectionId(String? config) {
  if (config == null) return null;
  return (jsonDecode(config) as Map<String, dynamic>)['targetCollectionId'] as String?;
}

/// A relation property value is a JSON array of target page ids (see
/// ARCHITECTURE.md).
List<String> decodeRelationValue(Object? raw) {
  if (raw is! List) return const [];
  return raw.cast<String>();
}
