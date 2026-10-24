import type { PickedFile } from '@turtle-base/platform';

import type { FileStore } from '../../../packages/file-store/file-store.ts';
import type { AttachmentsRepository } from './attachments-repository.ts';
import type { FileAccept } from './file-accept.ts';

/**
 * Stores picked files and attaches them to the page's field (`fieldId`) or,
 * without one, to its text. Files the field doesn't take (by type, or beyond
 * `maxCount`) are left out and returned by name, for telling the user.
 */
export async function attachPickedFiles(options: {
  files: FileStore;
  attachments: AttachmentsRepository;
  picked: readonly PickedFile[];
  pageId: string;
  fieldId?: string | null;
  accept: FileAccept;
  maxCount?: number | undefined;
}): Promise<{ ids: string[]; rejected: string[] }> {
  const ids: string[] = [];
  const rejected: string[] = [];
  for (const picked of options.picked) {
    if (options.maxCount !== undefined && ids.length >= options.maxCount) {
      rejected.push(picked.name);
      await picked.bytes.cancel();
      continue;
    }
    const stored = await options.files.import({ name: picked.name, bytes: picked.bytes });
    // Checked after storing: the type comes from the content, not from the name.
    if (!options.accept.accepts({ mimeType: stored.mimeType, fileName: picked.name })) {
      rejected.push(picked.name);
      continue;
    }
    ids.push(
      await options.attachments.create({
        pageId: options.pageId,
        fieldId: options.fieldId ?? null,
        file: {
          file_hash: stored.hash,
          name: picked.name,
          mime_type: stored.mimeType,
          size: stored.size,
          width: stored.width,
          height: stored.height,
        },
      }),
    );
  }
  return { ids, rejected };
}
