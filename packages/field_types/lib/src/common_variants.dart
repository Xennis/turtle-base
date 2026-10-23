import 'package:field_types/src/field_variant.dart';

/// Variants every turtle-base app offers - plugins may use them in their
/// collection templates, e.g. a URL field linking to the source.
final commonVariants = <FieldVariant<Object>>[urlVariant, emailVariant, phoneVariant];

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

/// A host with a dot, with or without a scheme (`example.com` counts).
bool isValidUrl(String value) {
  final withScheme = value.contains('://') ? value : 'https://$value';
  final uri = Uri.tryParse(withScheme);
  return uri != null && uri.host.isNotEmpty && uri.host.contains('.');
}
