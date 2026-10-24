import { escapeQuery, folderMimeType, type DriveClient, type DriveFile } from './drive-client.ts';

/** Folder lookups shared by the transports of one {@link DriveClient}: resolves (and creates) folder paths once. */
export class DriveFolders {
  readonly client: DriveClient;
  readonly #ids = new Map<string, Promise<string>>();

  constructor(client: DriveClient) {
    this.client = client;
  }

  /** The id of the folder at `path` from the Drive root, creating missing folders on the way. */
  async resolve(path: readonly string[]): Promise<string> {
    let parentId: string | undefined;
    for (const [i, name] of path.entries()) {
      const key = path.slice(0, i + 1).join('/');
      let id = this.#ids.get(key);
      if (id === undefined) {
        // Remembered as a promise, so two concurrent lookups don't create the folder twice.
        id = this.#findOrCreate(name, parentId);
        this.#ids.set(key, id);
        id.catch(() => this.#ids.delete(key));
      }
      parentId = await id;
    }
    if (parentId === undefined) throw new RangeError('Empty folder path');
    return parentId;
  }

  childFolders(parentId: string): Promise<DriveFile[]> {
    return this.client.listAll(`'${parentId}' in parents and mimeType='${folderMimeType}' and trashed=false`);
  }

  childFiles(parentId: string, name?: string): Promise<DriveFile[]> {
    const nameClause = name === undefined ? '' : ` and name='${escapeQuery(name)}'`;
    return this.client.listAll(
      `'${parentId}' in parents and mimeType!='${folderMimeType}' and trashed=false${nameClause}`,
    );
  }

  async #findOrCreate(name: string, parentId: string | undefined): Promise<string> {
    const parentClause = parentId === undefined ? '' : ` and '${parentId}' in parents`;
    const [existing] = await this.client.listAll(
      `name='${escapeQuery(name)}' and mimeType='${folderMimeType}' and trashed=false${parentClause}`,
    );
    return existing?.id ?? this.client.createFolder(name, parentId);
  }
}
