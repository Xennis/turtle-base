import { toast } from 'sonner';

import { useAppServices } from '../../../core/app-scope.tsx';
import { attachPickedFiles } from '../data/attach-files.ts';
import { FileAccept } from '../data/file-accept.ts';

/**
 * Lets the user pick files and attaches them to a page's field or text -
 * returns the new attachments' ids, empty when cancelled. Files that don't
 * fit are reported in a toast.
 */
export function usePickAndAttach(): (options: {
  pageId: string;
  fieldId?: string | null;
  accept?: FileAccept;
  maxCount?: number | undefined;
}) => Promise<string[]> {
  const { platform, files, attachments } = useAppServices();
  return async ({ pageId, fieldId = null, accept = FileAccept.any, maxCount }) => {
    try {
      const picked = await platform.pickFiles({
        multiple: maxCount !== 1,
        extensions: accept.isImagesOnly ? undefined : accept.dialogExtensions,
        imagesOnly: accept.isImagesOnly,
      });
      const { ids, rejected } = await attachPickedFiles({
        files,
        attachments,
        picked,
        pageId,
        fieldId,
        accept,
        maxCount,
      });
      if (rejected.length > 0) toast.error(`Not added: ${rejected.join(', ')}`);
      return ids;
    } catch (error) {
      toast.error(`Couldn't add the files: ${String(error)}`);
      return [];
    }
  };
}
