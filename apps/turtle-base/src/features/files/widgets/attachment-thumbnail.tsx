import { cn } from 'cn';
import { File } from 'lucide-react';
import { useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import type { Attachment } from '../../../core/database/schema.ts';
import { FileStore } from '../../../packages/file-store/file-store.ts';
import { isImage } from '../data/attachments-repository.ts';

/**
 * An attachment as a small square: its thumbnail for an image, else a file
 * icon. A thumbnail that isn't on this device (yet) falls back to the icon.
 */
export function AttachmentThumbnail({ attachment, className }: { attachment: Attachment; className?: string }) {
  const { files } = useAppServices();
  const [failed, setFailed] = useState(false);
  const showImage = isImage(attachment) && !failed;
  return (
    <span
      title={attachment.name}
      className={cn(
        'inline-flex size-7 shrink-0 items-center justify-center overflow-hidden rounded bg-muted',
        className,
      )}
    >
      {showImage ? (
        <img
          alt={attachment.name}
          src={files.urlOf(FileStore.thumbnailNameOf(attachment.file_hash))}
          className="size-full object-cover"
          onError={() => setFailed(true)}
        />
      ) : (
        <File className="size-4 text-muted-foreground" />
      )}
    </span>
  );
}

/** A tile's cover: the image's thumbnail filling the space, muted while there's none. */
export function AttachmentCover({ attachment }: { attachment: Attachment | undefined }) {
  const { files } = useAppServices();
  const [failed, setFailed] = useState(false);
  if (attachment === undefined || failed) return <div className="size-full bg-muted" />;
  return (
    <img
      alt={attachment.name}
      src={files.urlOf(FileStore.thumbnailNameOf(attachment.file_hash))}
      className="size-full bg-muted object-cover"
      onError={() => setFailed(true)}
    />
  );
}
