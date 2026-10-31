/**
 * The major version of this API. A plugin's manifest names the one it was
 * built against, and the app only loads plugins of a major it supports.
 */
export const pluginApiVersion = 1;

/**
 * What a release of a plugin says about itself - published as
 * `manifest.json` next to its bundle, see the package's README.
 */
export interface PluginManifest {
  /** The plugin's id, see `TurtlePlugin.id`. */
  readonly id: string;
  readonly name: string;

  /** Semver, e.g. `1.2.0`. */
  readonly version: string;

  /** See {@link pluginApiVersion}. */
  readonly apiVersion: number;
  readonly author: string;
  readonly description: string;
  readonly icon?: string;

  /** The bundle's file name, relative to the manifest's URL, e.g. `books.js`. */
  readonly main: string;

  /** Of the bundle, as lowercase hex. */
  readonly sha256: string;
  readonly permissions: PluginPermissions;
}

/** What a plugin may do beyond describing data - shown before it's installed. */
export interface PluginPermissions {
  /**
   * Host names `fetch` may reach, e.g. `openlibrary.org`. `*.example.org`
   * matches its subdomains, not `example.org` itself.
   */
  readonly network?: readonly string[];
}
