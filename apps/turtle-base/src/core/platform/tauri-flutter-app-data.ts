import { invoke } from '@tauri-apps/api/core';
import type { FlutterAppData, SqlRow } from '@turtle-base/platform';

/** The Flutter app's data through the shell (flutter.rs) - for the one-time import, only on the desktop. */
export async function findFlutterAppData(): Promise<FlutterAppData | undefined> {
  const location = await invoke<string | null>('flutter_find');
  if (location === null) return undefined;
  return {
    location,
    // The Flutter app stores no blobs - its rows hold only JSON values.
    query: (sql) => invoke<SqlRow[]>('flutter_query', { sql }),
    listFiles: () => invoke<string[]>('flutter_list_files'),
    readFile: async (name) => new Blob([await invoke<ArrayBuffer>('flutter_read_file', { name })]).stream(),
  };
}
