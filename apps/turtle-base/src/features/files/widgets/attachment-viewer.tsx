import { ExternalLink } from 'lucide-react';
import { useEffect, useState } from 'react';
import { toast } from 'sonner';

import { useAppServices } from '../../../core/app-scope.tsx';
import type { Attachment } from '../../../core/database/schema.ts';
import { Button } from '../../../core/ui/button.tsx';
import { Dialog, DialogContent, DialogTitle } from '../../../core/ui/dialog.tsx';
import { FileStore } from '../../../packages/file-store/file-store.ts';
import { isImage } from '../data/attachments-repository.ts';

/** Opens an attachment: an image in the viewer, anything else with the system's app. */
export function useOpenAttachment(): (attachment: Attachment, showImage: (attachment: Attachment) => void) => void {
  const openExternally = useOpenExternally();
  return (attachment, showImage) => (isImage(attachment) ? showImage(attachment) : void openExternally(attachment));
}

/**
 * Opens the original with the system's app. It may be a thumbnail only on
 * this device (not synced yet) - then it's downloaded first, when connected.
 */
export function useOpenExternally(): (attachment: Attachment) => Promise<void> {
  const { platform, files, sync } = useAppServices();
  return async (attachment) => {
    if (!(await files.has(attachment.file_hash)) && sync.isConnected) {
      toast(`Downloading ${attachment.name}…`);
      await sync.fetchFile(attachment.file_hash);
    }
    if (!(await files.has(attachment.file_hash))) {
      toast.error(`${attachment.name} is not available offline`);
      return;
    }
    await platform.openFile(attachment.file_hash, attachment.name).catch(() => {
      toast.error(`No app found to open ${attachment.name}`);
    });
  };
}

/**
 * An image attachment full size. Where the original isn't on this device, its
 * thumbnail shows while the original is downloaded (when connected), or for good.
 */
export function AttachmentViewer({ attachment, onClose }: { attachment: Attachment; onClose: () => void }) {
  const { files, sync } = useAppServices();
  const openExternally = useOpenExternally();
  const thumbnail = files.urlOf(FileStore.thumbnailNameOf(attachment.file_hash));
  const [fetched, setFetched] = useState(false);

  useEffect(() => {
    let current = true;
    void (async () => {
      if (await files.has(attachment.file_hash)) return;
      if ((await sync.fetchFile(attachment.file_hash)) && current) setFetched(true);
    })();
    return () => {
      current = false;
    };
  }, [files, sync, attachment.file_hash]);

  return (
    <Dialog open onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="flex max-h-[90vh] flex-col gap-3 sm:max-w-[90vw]">
        <div className="flex items-center gap-2 pr-8">
          <DialogTitle className="min-w-0 flex-1 truncate">{attachment.name}</DialogTitle>
          <Button variant="ghost" size="sm" onClick={() => void openExternally(attachment)}>
            <ExternalLink />
            Open with…
          </Button>
        </div>
        <img
          // Loaded again once a missing original has arrived.
          key={String(fetched)}
          alt={attachment.name}
          src={files.urlOf(attachment.file_hash)}
          className="min-h-0 flex-1 object-contain"
          onError={(event) => {
            if (event.currentTarget.src !== thumbnail) event.currentTarget.src = thumbnail;
          }}
        />
      </DialogContent>
    </Dialog>
  );
}
