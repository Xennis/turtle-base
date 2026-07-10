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
