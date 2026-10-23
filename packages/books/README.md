# books

Book-related extensions for turtle-base. Currently one field type variant:

- `books.isbn` (`isbnVariant`): a text field holding an ISBN-10 or ISBN-13. Input is normalized (separators removed), validated by its check digit and stored as digits only, e.g. `9783453317178`. It's shown with the prefix split off (`978-3453317178`) and links to Open Library.

The package exports `booksPlugin` (see `turtle_plugin`), which the app registers in its `PluginRegistry` (see `apps/turtle_base/lib/main.dart`). A device without this package reads such fields as plain text.
