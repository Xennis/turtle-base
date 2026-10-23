# field_types

The API for field type variants: semantics such as an ISBN or an email address on top of one of turtle-base's built-in base types (text, number). A variant validates, normalizes and formats values but is stored exactly like its base type, so a device without the package contributing it still reads the field as plain text or number.

Plugins list their variants in `TurtlePlugin.variants` (see `turtle_plugin`), and the app registers them at startup. The variants every app offers (`url`, `email`, `phone`) live here too as `commonVariants`, so plugins can use them in their collection templates. See `.local/FIELD_TYPES.md` for the overall field type concept.

```dart
final emailVariant = TextVariant.pattern(
  id: 'email',
  label: 'Email',
  pattern: RegExp(r'[^@\s]+@[^@\s]+\.[^@\s]+'),
  message: 'Enter a valid email address',
  inputHint: InputHint.email,
  link: (value) => Uri(scheme: 'mailto', path: value),
);
```
