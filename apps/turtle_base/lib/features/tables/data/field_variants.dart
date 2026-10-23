import 'package:field_types/field_types.dart';
import 'package:turtle_base/features/tables/data/field_validation.dart';

/// Variants the app itself ships - packages add theirs via
/// FieldTypeRegistry.
final appFieldVariants = <FieldVariant<Object>>[urlVariant, emailVariant, phoneVariant, ratingVariant];

final urlVariant = TextVariant(
  id: 'url',
  label: 'URL',
  inputHint: InputHint.url,
  normalize: (value) => value.trim(),
  validate: (value) => isValidUrl(value) ? null : 'Enter a valid URL, e.g. example.com',
  link: (value) => Uri.parse(value.contains('://') ? value : 'https://$value'),
);

final emailVariant = TextVariant.pattern(
  id: 'email',
  label: 'Email',
  pattern: RegExp(r'[^@\s]+@[^@\s]+\.[^@\s]+'),
  message: 'Enter a valid email address',
  inputHint: InputHint.email,
  normalize: (value) => value.trim(),
  link: (value) => Uri(scheme: 'mailto', path: value),
);

final phoneVariant = TextVariant.pattern(
  id: 'phone',
  label: 'Phone',
  pattern: RegExp(r'\+?[0-9][0-9 ()/.-]{2,}'),
  message: 'Enter a valid phone number, e.g. +49 30 1234567',
  inputHint: InputHint.phone,
  normalize: (value) => value.trim(),
  link: (value) => Uri(scheme: 'tel', path: value.replaceAll(RegExp(r'[^0-9+]'), '')),
);

/// A whole number shown as stars - 1 to 5 by default, adjustable via the
/// number config like any number field.
final ratingVariant = NumberVariant(
  id: 'rating',
  label: 'Rating',
  configPreset: const {'min': 1, 'max': 5, 'decimals': 0},
  validate: (value) => value == value.roundToDouble() ? null : 'Enter a whole number',
  format: (value) => '★' * value.round().clamp(0, 100),
);
