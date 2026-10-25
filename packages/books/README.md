# @turtle-base/books

The Books plugin for turtle-base: a reading list instead of Goodreads. The package exports `booksPlugin` (see `@turtle-base/plugin-api`), which the app registers in its `PluginRegistry` (see the app's entry point). Adding it on the Plugins page creates a space "Books" with:

- **Reading list** (`readingList`): Title, Status (Want to read, Reading, Read, Abandoned), Author, Year, ISBN, Cover, Pages, Started, Finished, Rating (1-5) and the Open Library link.
- **Add book** (`openLibraryLookup`): searches Open Library by title, author or ISBN (`OpenLibraryClient`, no API key, through the `fetch` the app passes in). The picked book becomes an entry with status "Want to read" and its cover downloaded. A book whose work is already in the list opens that entry instead.

Title, cover and ISBN come from the edition Open Library ranks best for the query, e.g. the German one for "Der Wüstenplanet" or exactly the edition of a searched ISBN. Year and pages are the work's (first publication, median page count).

It also contributes one field type variant:

- `books.isbn` (`isbnVariant`): a text field holding an ISBN-10 or ISBN-13. Input is normalized (separators removed), validated by its check digit and stored as digits only, e.g. `9783453317178`. It's shown with the prefix split off (`978-3453317178`) and links to Open Library.

A device without this package reads the reading list as an ordinary collection and ISBN fields as plain text - it only lacks the "Add book" button.
