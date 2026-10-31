# AGENTS.md

## Language

Code (identifiers, comments) is always written in English.

## Commits

Format: `type(scope): Description`

- Types: `chore`, `feat`, `fix`
- Scope: default `app`; use the app folder name (e.g. `shell`) when a change only touches that app, or the package folder name (e.g. `crdt-file-sync-google-drive`) when a change only touches that package

Example: `feat(shell): Keep secrets in the OS keyring`

## Tooling

Tool versions (Node, pnpm, Rust) are managed via [mise](https://mise.jdx.dev/) - see `mise.toml`. The workspace uses Vite+ (`vp`) for checks, tests and builds, with strict TypeScript; the shell's Rust code is checked with `cargo fmt`/`clippy` and tested with `cargo test` - `mise run check`/`test` run both.

## Platforms

Linux, macOS and Android are the supported platforms: one React app, run by one Tauri 2 shell on the desktop and on Android. Don't add other platforms (e.g. iOS, web) - verify changes via `mise run run-desktop` and `mise run desktop-smoke`, for anything responsive/layout-related also in a narrow window and on Android (`mise run run-android`, or `mise run mobile-smoke` on an emulator); fall back to `mise run check`/`mise run test` when no display is available.

## Monorepo

The repo is a pnpm workspace (root `package.json`, one shared `pnpm-lock.yaml`; run `mise run install` in the root). Dependency versions are kept once, in the catalog of `pnpm-workspace.yaml` (members refer to them as `catalog:`).

- `apps/turtle-base/`: the app - React UI and app logic, the page both shells show
- `apps/shell/`: the Tauri shell - Rust commands in `src-tauri/src`, the Android project in `src-tauri/gen/android` (with its Kotlin plugin), packaged with `tauri build`
- `packages/<name>/`: local packages
- `plugins/<name>/`: plugins, released on their own and installed from the catalog (`catalog/catalog.json`) - never a dependency of the app. They depend only on `@turtle-base/plugin-api` (and npm packages) and compile without the DOM (`lib: ["ES2024"]` plus `@turtle-base/plugin-api/globals`), so they can move into a sandbox later.

Dependencies point from apps to packages, never back. The app talks to the platform it runs on only through the `Platform` interface of `packages/platform` (SQLite, files, prefs, secrets, network, sign-in); the shell implements it - official Tauri plugins first, the shell's own Rust (or, on Android, Kotlin) only where none fits. Storage adapters are `packages/crdt-file-sync-<storage>` packages that implement `SyncTransport` from `crdt-file-sync-transport`; the CRDT/sync logic (`SyncController`, `sql-crdt`'s use) stays in the app. A package has a `README.md` for anything specific to it (e.g. its configuration) and exposes its API via one barrel file `src/index.ts` (internals in `src/`, test helpers in `src/testing.ts` as the `/testing` export).

`mise run check`, `fix` and `test` run over all members automatically.

## Structure

Each `apps/turtle-base/src/features/<name>/` folder is split into:

- `data/`: repositories and DB-adjacent types (e.g. `*-repository.ts`, types backing a column) - plain TypeScript, tested on `node:sqlite`
- `widgets/`: everything UI-facing - views, dialogs, hooks and UI-state notifiers

Only add the subfolders a feature actually needs (e.g. a feature with no UI doesn't need `widgets/`). No further nesting (e.g. no separate `screens/` or `dialogs/`) - file names are kebab-case and carry that distinction via suffixes like `-repository.ts`, `-view.tsx`, `-dialog.tsx`, `-page.tsx`. Tests sit next to the code they test (`*.test.ts`).
