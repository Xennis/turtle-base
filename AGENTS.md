# AGENTS.md

## Language

Code (identifiers, comments) is always written in English.

## Commits

Format: `type(scope): Description`

- Types: `chore`, `feat`, `fix`
- Scope: default `app`; use the platform folder name (e.g. `linux`, `android`) when a change only touches that platform folder

Example: `chore(app): Init Flutter project with Linux as platform`

## Tooling

Tool versions (e.g. Flutter) are managed via [mise](https://mise.jdx.dev/) — see `mise.toml`.

## Claude Code skills

Skill content itself isn't checked in - only `skills-lock.json` is tracked. Run
`mise run skills-install` to (re)install the skills it references into `.claude/skills/`
(gitignored).

## Platforms

Linux, macOS and Android are the supported Flutter platforms. Don't run
`flutter create --platforms=...` for other platforms (e.g. web, iOS) and don't add platform
folders like `web/` — verify changes via `flutter run -d linux` and, for anything
responsive/layout-related, also on Android (emulator `vPixel_10`, or `flutter run -d android`)
and macOS (`flutter run -d macos`, or `mise run run-macos` for Drive sync config); fall back to
`flutter analyze`/`flutter test` when no display is available.

## Structure

Each `lib/features/<name>/` folder is split into:

- `data/`: repositories and DB-adjacent types (e.g. `*_repository.dart`, enums backing a column)
- `widgets/`: everything UI-facing — views, dialogs, and UI-state `ChangeNotifier`s

Only add the subfolders a feature actually needs (e.g. a feature with no UI state doesn't need `widgets/`). No further nesting (e.g. no separate `screens/` or `dialogs/`) — filenames already carry that distinction via suffixes like `_repository.dart`, `_view.dart`, `_dialog.dart`.
