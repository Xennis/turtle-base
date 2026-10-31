# @turtle-base/plugin-api

The API for turtle-base plugins. A plugin only describes data and offers pure functions; the app does all the writing, so sync, validation and soft-delete work as for the user's own input. Plugins are plain TypeScript, without React.

A `TurtlePlugin` contributes:

- `variants`: field type variants, see `@turtle-base/field-types` (re-exported here).
- `collections`: `CollectionTemplate`s. Adding the plugin creates a space with one collection per template, each with the template's fields.
- per collection an optional `EntryLookup`: a search in an external source (e.g. Open Library) whose results (`EntryDraft`) the user picks to add an entry.

A lookup reaches the network only through the `PluginFetch` in its `LookupContext` - a small part of `fetch` without DOM types, limited to the hosts of the plugin's manifest. Errors cross by name, not by class: throw a `LookupError` and the app shows its message (`isLookupError`). `@turtle-base/plugin-api/testing` has `responseOf` to answer a lookup's requests in tests.

## Manifest

A plugin is released as two files: its bundle (one ES module without imports, `export default` of the `TurtlePlugin`) and a `manifest.json` (`PluginManifest`) next to it:

```json
{
  "id": "books",
  "name": "Books",
  "version": "1.0.0",
  "apiVersion": 1,
  "author": "Xennis",
  "description": "Track the books you want to read, are reading and have read.",
  "icon": "📚",
  "main": "books.js",
  "sha256": "<hex of books.js>",
  "permissions": { "network": ["openlibrary.org", "covers.openlibrary.org"] }
}
```

`apiVersion` is the major version of this package (`pluginApiVersion`); the app refuses majors it doesn't know. `permissions.network` lists the hosts `PluginFetch` may reach, and the files of an `EntryDraft` may come from - shown to the user before installing.

## Ids

Everything a plugin brings in has an id derived from the plugin's `id`, with `.` as separator. That's how the app recognizes a plugin's rows again, without a column of its own. Plugin ids, template keys and field keys therefore never contain a dot.

| What | Id | Example |
|---|---|---|
| Variant | `<plugin>.<key>` | `books.isbn` |
| Space | `<plugin>.<uuid>` | `books.6f1c…` |
| Collection | `<space-id>.<template-key>` | `books.6f1c….reading_list` |
| Field | `<collection-id>.<field-key>` | `books.6f1c….reading_list.status` |
| Select option | `<option-key>` | `read` |

Entries and attachments keep random ids - they're the user's data. Adding a plugin twice creates a second space with a fresh uuid.

```ts
export const booksPlugin: TurtlePlugin = {
  id: 'books',
  name: 'Books',
  description: 'Track the books you read.',
  icon: '📚',
  variants: [isbnVariant],
  collections: [readingList],
};
```
