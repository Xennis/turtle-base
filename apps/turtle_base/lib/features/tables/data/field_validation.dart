/// Value checks shared by the base field types and the app's variants
/// (see base_field_type.dart, field_variants.dart).
library;

bool isValidUrl(String value) {
  final withScheme = value.contains('://') ? value : 'https://$value';
  final uri = Uri.tryParse(withScheme);
  return uri != null && uri.host.isNotEmpty && uri.host.contains('.');
}

bool isValidNumber(String value) => num.tryParse(value) != null;
