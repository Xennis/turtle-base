import { createReactBlockSpec } from '@blocknote/react';
import { useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { useDbQuery } from '../../../core/database/use-db-query.ts';
import type { Attachment } from '../../../core/database/schema.ts';
import { FileStore } from '../../../packages/file-store/file-store.ts';
import { attachmentBlockType, attachmentIdProp } from '../../pages/widgets/block-sync.ts';
import { isImage } from '../data/attachments-repository.ts';
import { AttachmentThumbnail } from './attachment-thumbnail.tsx';
import { AttachmentViewer, useOpenExternally } from './attachment-viewer.tsx';
import { formatFileSize } from './files-field-value.tsx';

/**
 * A file in a page's text: an image shown inline, any other file as a row
 * with its name and size. The block only holds the attachment's id - the file
 * itself is in the store, see block-sync.ts's syncAttachmentsFromDocument.
 */
export const attachmentBlock = createReactBlockSpec(
  {
    type: attachmentBlockType,
    propSchema: { [attachmentIdProp]: { default: '' } },
    content: 'none',
  },
  {
    render: ({ block }) => <AttachmentBlockView attachmentId={block.props.attachmentId} />,
  },
);

function AttachmentBlockView({ attachmentId }: { attachmentId: string }) {
  const { attachments } = useAppServices();
  const { data: attachment, isPending } = useDbQuery({
    tables: ['attachments'],
    key: ['id', attachmentId],
    query: async () => (await attachments.byId(attachmentId)) ?? null,
  });
  if (isPending) return <div className="h-12" />;
  if (attachment === null || attachment === undefined) {
    return <p className="text-sm text-muted-foreground">File not available</p>;
  }
  return isImage(attachment) ? <ImageContent attachment={attachment} /> : <FileRow attachment={attachment} />;
}

/** At its own aspect ratio (known before loading, so the text doesn't jump), at most 420 pixels high and its own width. */
function ImageContent({ attachment }: { attachment: Attachment }) {
  const { files } = useAppServices();
  const [viewing, setViewing] = useState(false);
  const thumbnail = files.urlOf(FileStore.thumbnailNameOf(attachment.file_hash));
  const ratio =
    attachment.width !== null && attachment.height !== null && attachment.height > 0
      ? attachment.width / attachment.height
      : 4 / 3;
  return (
    <>
      <button
        type="button"
        contentEditable={false}
        aria-label={`Open ${attachment.name}`}
        onClick={() => setViewing(true)}
        className="block max-h-[420px] overflow-hidden rounded-lg bg-muted"
        // Never wider than the image itself - a small one isn't blown up.
        style={{ aspectRatio: ratio, width: `min(100%, ${Math.min(420 * ratio, attachment.width ?? Infinity)}px)` }}
      >
        <img
          alt={attachment.name}
          src={files.urlOf(attachment.file_hash)}
          className="size-full object-cover"
          onError={(event) => {
            if (event.currentTarget.src !== thumbnail) event.currentTarget.src = thumbnail;
          }}
        />
      </button>
      {viewing && <AttachmentViewer attachment={attachment} onClose={() => setViewing(false)} />}
    </>
  );
}

function FileRow({ attachment }: { attachment: Attachment }) {
  const openExternally = useOpenExternally();
  return (
    <button
      type="button"
      contentEditable={false}
      onClick={() => void openExternally(attachment)}
      className="flex max-w-full items-center gap-3 rounded-lg border p-2 text-left hover:bg-muted"
    >
      <AttachmentThumbnail attachment={attachment} className="size-9" />
      <span className="min-w-0">
        <span className="block truncate text-sm">{attachment.name}</span>
        <span className="block text-xs text-muted-foreground">{formatFileSize(attachment.size)}</span>
      </span>
    </button>
  );
}
