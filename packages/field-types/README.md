# @turtle-base/field-types

The API for field type variants: semantics such as an ISBN or an email address on top of one of turtle-base's built-in base types (text, number). A variant validates, normalizes and formats values but is stored exactly like its base type, so a device without the package contributing it still reads the field as plain text or number.

Plugins list their variants in `TurtlePlugin.variants` (see `@turtle-base/plugin-api`), and the app registers them at startup. The variants every app offers (`url`, `email`, `phone`) live here too as `commonVariants`, so plugins can use them in their collection templates. See `.local/FIELD_TYPES.md` for the overall field type concept.

```ts
export const emailVariant = patternTextVariant({
  id: 'email',
  label: 'Email',
  pattern: /[^@\s]+@[^@\s]+\.[^@\s]+/,
  message: 'Enter a valid email address',
  inputHint: 'email',
  link: (value) => new URL(`mailto:${value}`),
});
```

A variant is a discriminated union over `baseTypeId` (`'text'` or `'number'`), so checking it narrows the value type of its hooks.
