# @turtle-base/plugin-catalog

Where plugins come from: the plugin catalog (`catalog/catalog.json` in this repo, fetched from `catalogUrl`), the manifests of released plugins and their bundles - fetched with the `fetch` the app passes in, and checked.

- `fetchCatalog`/`parseCatalog`: the catalog lists each plugin with the URL of its release's manifest, pinned to a version and the bundle's SHA-256. An id may appear once.
- `fetchManifest`/`parseManifest`: a `PluginManifest` (see `@turtle-base/plugin-api`). Rejects manifests of another major of the plugin API and a `main` that isn't a plain file name next to the manifest.
- `fetchBundle`: the bundle next to the manifest, checked against the manifest's hash.
- `validatePlugin`: whether a bundle's default export is a `TurtlePlugin` - its shape, and the id rules of plugin-api's README.

Plugins only come over https. Errors meant for the user are `PluginSourceError`s.
