import 'package:field_types/field_types.dart';
import 'package:turtle_base/features/tables/data/field_validation.dart';

/// Variants the app itself ships - packages add theirs via
/// FieldTypeRegistry.
final appFieldVariants = <FieldVariant<Object>>[urlVariant];

final urlVariant = TextVariant(
  id: 'url',
  label: 'URL',
  inputHint: InputHint.url,
  normalize: (value) => value.trim(),
  validate: (value) => isValidUrl(value) ? null : 'Enter a valid URL, e.g. example.com',
  link: (value) => Uri.parse(value.contains('://') ? value : 'https://$value'),
);
