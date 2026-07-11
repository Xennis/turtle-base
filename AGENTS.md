# AGENTS.md

## Language

Code (identifiers, comments) is always written in English.

## Commits

Format: `type(scope): Description`

- Types: `chore`, `feat`, `fix`
- Scope: default `app`; use the platform folder name (e.g. `linux`) when a change only touches that platform folder (`linux/`, later `android/`, ...)

Example: `chore(app): Init Flutter project with Linux as platform`

## Tooling

Tool versions (e.g. Flutter) are managed via [mise](https://mise.jdx.dev/) — see `mise.toml`.

## Platforms

Linux is the only supported Flutter platform. Don't run `flutter create --platforms=...` for
other platforms (e.g. web, android) and don't add platform folders like `web/` — verify changes
via `flutter run -d linux` (or `flutter analyze`/`flutter test` when no display is available).

## Structure

Each `lib/features/<name>/` folder is split into:

- `data/`: repositories and DB-adjacent types (e.g. `*_repository.dart`, enums backing a column)
- `widgets/`: everything UI-facing — views, dialogs, and UI-state `ChangeNotifier`s

Only add the subfolders a feature actually needs (e.g. a feature with no UI state doesn't need `widgets/`). No further nesting (e.g. no separate `screens/` or `dialogs/`) — filenames already carry that distinction via suffixes like `_repository.dart`, `_view.dart`, `_dialog.dart`.
