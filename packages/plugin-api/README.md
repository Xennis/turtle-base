# @turtle-base/plugin-api

The API for turtle-base plugins. A plugin only describes data and offers pure functions; the app does all the writing, so sync, validation and soft-delete work as for the user's own input. Plugins are plain TypeScript, without React.

A `TurtlePlugin` contributes:

- `variants`: field type variants, see `@turtle-base/field-types` (re-exported here).
- `collections`: `CollectionTemplate`s. Adding the plugin creates a space with one collection per template, each with the template's fields.
- per collection an optional `EntryLookup`: a search in an external source (e.g. Open Library) whose results (`EntryDraft`) the user picks to add an entry.

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
