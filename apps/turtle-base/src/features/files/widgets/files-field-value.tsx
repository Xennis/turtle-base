import { MoreHorizontal, Plus } from 'lucide-react';
import { useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { useDbQuery } from '../../../core/database/use-db-query.ts';
import type { Attachment } from '../../../core/database/schema.ts';
import { Button } from '../../../core/ui/button.tsx';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '../../../core/ui/dropdown-menu.tsx';
import type { FileAccept } from '../data/file-accept.ts';
import { AttachmentThumbnail } from './attachment-thumbnail.tsx';
import { AttachmentViewer, useOpenAttachment, useOpenExternally } from './attachment-viewer.tsx';
import { usePickAndAttach } from './use-pick-and-attach.ts';

/** A files field's value on an entry's page: its files as tiles to open, reorder and remove, and one to add more. */
export function FilesFieldValue(props: {
  pageId: string;
  fieldId: string;
  accept: FileAccept;
  maxFiles: number | undefined;
}) {
  const { attachments } = useAppServices();
  const pickAndAttach = usePickAndAttach();
  const open = useOpenAttachment();
  const openExternally = useOpenExternally();
  const [viewing, setViewing] = useState<Attachment | undefined>();
  const { data: list = [] } = useDbQuery({
    tables: ['attachments'],
    key: ['field', props.pageId, props.fieldId],
    query: () => attachments.listInField(props.pageId, props.fieldId),
  });
  const room = props.maxFiles === undefined ? undefined : props.maxFiles - list.length;

  function move(index: number, by: -1 | 1) {
    const ids = list.map((attachment) => attachment.id);
    const [id] = ids.splice(index, 1);
    if (id === undefined) return;
    ids.splice(index + by, 0, id);
    void attachments.reorderAll(ids);
  }

  return (
    <div className="flex flex-wrap gap-2 py-1">
      {list.map((attachment, index) => (
        <div
          key={attachment.id}
          className="group relative"
          title={`${attachment.name} (${formatFileSize(attachment.size)})`}
        >
          <button type="button" aria-label={`Open ${attachment.name}`} onClick={() => open(attachment, setViewing)}>
            <AttachmentThumbnail attachment={attachment} className="size-18" />
          </button>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="secondary"
                size="icon-xs"
                aria-label={`More for ${attachment.name}`}
                className="absolute top-1 right-1 opacity-0 group-hover:opacity-100 focus-visible:opacity-100 data-[state=open]:opacity-100"
              >
                <MoreHorizontal />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onSelect={() => void openExternally(attachment)}>Open with…</DropdownMenuItem>
              {index > 0 && <DropdownMenuItem onSelect={() => move(index, -1)}>Move left</DropdownMenuItem>}
              {index < list.length - 1 && (
                <DropdownMenuItem onSelect={() => move(index, 1)}>Move right</DropdownMenuItem>
              )}
              <DropdownMenuItem variant="destructive" onSelect={() => void attachments.softDelete(attachment.id)}>
                Remove
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      ))}
      {(room === undefined || room > 0) && (
        <Button
          variant="outline"
          aria-label="Add file"
          className="size-18"
          onClick={() =>
            void pickAndAttach({ pageId: props.pageId, fieldId: props.fieldId, accept: props.accept, maxCount: room })
          }
        >
          <Plus />
        </Button>
      )}
      {viewing !== undefined && <AttachmentViewer attachment={viewing} onClose={() => setViewing(undefined)} />}
    </div>
  );
}

export function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}
