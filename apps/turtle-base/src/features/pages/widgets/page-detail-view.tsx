import { filterSuggestionItems } from '@blocknote/core/extensions';
import {
  getDefaultReactSlashMenuItems,
  SuggestionMenuController,
  useCreateBlockNote,
  type DefaultReactSuggestionItem,
} from '@blocknote/react';
import { BlockNoteView } from '@blocknote/shadcn';
import { ArrowLeft, File, Image, Paperclip, SmilePlus, Trash2 } from 'lucide-react';
import { useEffect, useMemo, useRef, useState, type ComponentProps } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { useDbQuery } from '../../../core/database/use-db-query.ts';
import type { Block, Page } from '../../../core/database/schema.ts';
import { Button } from '../../../core/ui/button.tsx';
import { Input } from '../../../core/ui/input.tsx';
import { useIsDark } from '../../../core/theme/use-is-dark.ts';
import { FileAccept } from '../../files/data/file-accept.ts';
import { usePickAndAttach } from '../../files/widgets/use-pick-and-attach.ts';
import { ConfirmDialog } from '../../shell/widgets/confirm-dialog.tsx';
import { BlocksRepository } from '../data/blocks-repository.ts';
import { buildDocument, hiddenBlockIds, type EditorBlock } from './block-document.ts';
import { blockEditorOf, pageSchema } from './block-editor.ts';
import {
  attachmentBlockType,
  attachmentIdProp,
  syncAttachmentsFromDocument,
  syncBlocksFromDocument,
} from './block-sync.ts';
import { PagePropertiesHeader } from './page-properties-header.tsx';

/** How long typing pauses before the blocks are written - not every keystroke is a sync change. */
const syncDelayMs = 500;

/**
 * A page - freestanding or a collection entry, they're the same thing - with
 * its title, an entry's field values, and its text in the block editor.
 */
export function PageDetailView(props: {
  pageId: string;
  onDeleted: () => void;
  onOpenCollection: (collectionId: string) => void;
}) {
  const { pages, database } = useAppServices();
  const { data: page } = useDbQuery({ tables: ['pages'], key: [props.pageId], query: () => pages.byId(props.pageId) });
  const { data: blocks } = useDbQuery({
    tables: ['blocks'],
    key: ['page', props.pageId],
    query: () => new BlocksRepository(database).listActiveInPage(props.pageId),
  });
  if (page === undefined || blocks === undefined) return null;
  // Keyed, so the editor starts over with the right content when another page opens.
  return <PageEditor key={page.id} page={page} storedBlocks={blocks} {...props} />;
}

function PageEditor(props: {
  page: Page;
  storedBlocks: readonly Block[];
  onDeleted: () => void;
  onOpenCollection: (collectionId: string) => void;
}) {
  const { page } = props;
  const { pages, database, theme, attachments } = useAppServices();
  const [deleting, setDeleting] = useState(false);
  const blocks = new BlocksRepository(database);
  const pickAndAttach = usePickAndAttach();
  const editor = useCreateBlockNote({ schema: pageSchema }, []);
  const blockEditor = useMemo(() => blockEditorOf(editor), [editor]);
  // BlockNote's own schema types don't satisfy its view's constraint under exactOptionalPropertyTypes.
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion
  const viewEditor = editor as unknown as ComponentProps<typeof BlockNoteView>['editor'];
  const knownTypes = new Set(Object.keys(editor.schema.blockSchema));
  const pendingSync = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  // Each block written refreshes the stored blocks - half-written states that must not replace the editor's.
  const writing = useRef(0);
  const dark = useIsDark(theme);

  async function syncNow() {
    pendingSync.current = undefined;
    writing.current += 1;
    try {
      await writeBlocks();
    } finally {
      writing.current -= 1;
    }
  }

  async function writeBlocks() {
    const current = await blocks.listActiveInPage(page.id);
    await syncBlocksFromDocument({
      blocks,
      pageId: page.id,
      document: blockEditor.document(),
      currentBlocks: current,
      untouched: hiddenBlockIds(current, knownTypes),
    });
    const replacements = await syncAttachmentsFromDocument({
      attachments,
      pageId: page.id,
      document: blockEditor.document(),
    });
    const replace = (nodes: readonly EditorBlock[]) => {
      for (const node of nodes) {
        const oldId = node.props[attachmentIdProp];
        const newId =
          node.type === attachmentBlockType && typeof oldId === 'string' ? replacements.get(oldId) : undefined;
        if (newId !== undefined) blockEditor.setProps(node.id, { [attachmentIdProp]: newId });
        replace(node.children);
      }
    };
    replace(blockEditor.document());
  }

  /** Picks files and inserts them where the cursor is - captured first, the file dialog takes the focus. */
  async function attach(accept: FileAccept) {
    const at = blockEditor.cursorBlockId();
    const ids = await pickAndAttach({ pageId: page.id, accept });
    blockEditor.insertAfter(
      ids.map((id) => ({ type: attachmentBlockType, props: { [attachmentIdProp]: id } })),
      at,
    );
  }

  const mediaItems: DefaultReactSuggestionItem[] = [
    {
      title: 'Image',
      subtext: 'Add an image from this device',
      aliases: ['image', 'photo', 'picture'],
      group: 'Media',
      icon: <Image size={18} />,
      onItemClick: () => void attach(FileAccept.images),
    },
    {
      title: 'File',
      subtext: 'Attach a file from this device',
      aliases: ['file', 'attachment', 'upload'],
      group: 'Media',
      icon: <File size={18} />,
      onItemClick: () => void attach(FileAccept.any),
    },
  ];

  // The stored blocks as the editor's content - first when the page opens, then whenever they change from
  // elsewhere (e.g. a sync merged another device's edit). Never while the user types here or a local change is
  // still to be written or being written: that would move the cursor or bring back a half-written state, and
  // the merge per block already happened in the database.
  useEffect(() => {
    if (pendingSync.current !== undefined || writing.current > 0 || blockEditor.isFocused()) return;
    const stored = buildDocument(props.storedBlocks, new Set(Object.keys(editor.schema.blockSchema)));
    if (JSON.stringify(stored) === JSON.stringify(blockEditor.document().map(toEditorBlock))) return;
    // An empty page keeps the editor's empty paragraph.
    if (stored.length > 0) blockEditor.replaceAll(stored);
  }, [editor, blockEditor, props.storedBlocks]);

  // Writes what's still pending when the page closes.
  useEffect(
    () => () => {
      if (pendingSync.current === undefined) return;
      clearTimeout(pendingSync.current);
      void syncNow();
    },
    // oxlint-disable-next-line react/exhaustive-deps -- runs once on unmount, with the editor of this page
    [],
  );

  return (
    <div className="mx-auto flex w-full max-w-4xl flex-col gap-4 px-4 py-4 sm:px-16 sm:py-6">
      <div className="flex items-center gap-1">
        {page.collection_id !== null && (
          <Button
            variant="ghost"
            size="icon"
            aria-label="Back to collection"
            onClick={() => page.collection_id !== null && props.onOpenCollection(page.collection_id)}
          >
            <ArrowLeft />
          </Button>
        )}
        <div className="flex-1" />
        <Button variant="ghost" size="icon" aria-label="Attach file" onClick={() => void attach(FileAccept.any)}>
          <Paperclip />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          aria-label={page.collection_id === null ? 'Delete page' : 'Delete entry'}
          onClick={() => setDeleting(true)}
        >
          <Trash2 />
        </Button>
      </div>
      <TitleRow page={page} />
      {page.collection_id !== null && <PagePropertiesHeader page={page} collectionId={page.collection_id} />}
      {/* The editor's gutter for its block handles lies in the page's padding, so text lines up with the title. */}
      <div className="min-h-64 sm:-mx-[54px]">
        <BlockNoteView
          editor={viewEditor}
          theme={dark ? 'dark' : 'light'}
          slashMenu={false}
          onChange={() => {
            clearTimeout(pendingSync.current);
            pendingSync.current = setTimeout(() => void syncNow(), syncDelayMs);
          }}
        >
          <SuggestionMenuController
            triggerCharacter="/"
            getItems={(query) =>
              Promise.resolve(
                filterSuggestionItems(
                  [
                    ...getDefaultReactSlashMenuItems(viewEditor).filter((item) => item.group !== 'Media'),
                    ...mediaItems,
                  ],
                  query,
                ),
              )
            }
          />
        </BlockNoteView>
      </div>
      <ConfirmDialog
        open={deleting}
        title={page.collection_id === null ? 'Delete this page?' : 'Delete this entry?'}
        message="It will stop being shown until it's restored - there's no trash to restore it from yet."
        onOpenChange={setDeleting}
        onConfirm={async () => {
          await pages.softDelete(page.id);
          // An entry goes back to its collection, a page to wherever the shell sends it.
          if (page.collection_id === null) props.onDeleted();
          else props.onOpenCollection(page.collection_id);
        }}
      />
    </div>
  );
}

/** The editor's block reduced to what's stored, for comparing with the database. */
function toEditorBlock(block: EditorBlock): EditorBlock {
  const { id, type, props, content, children } = block;
  return { id, type, props, ...(content === undefined ? {} : { content }), children: children.map(toEditorBlock) };
}

/** The icon (an emoji, typed or picked from the system's emoji keyboard) and the title. */
function TitleRow({ page }: { page: Page }) {
  const { pages } = useAppServices();
  const [icon, setIcon] = useState(page.icon ?? '');
  const [title, setTitle] = useState(page.title);

  function saveIcon() {
    const trimmed = icon.trim();
    if (trimmed !== (page.icon ?? '')) void pages.setIcon(page.id, trimmed.length === 0 ? null : trimmed);
  }

  function saveTitle() {
    if (title.trim() !== page.title) void pages.rename(page.id, title.trim());
  }

  return (
    <div className="flex items-center gap-2">
      <div className="relative">
        {/* An emoji placeholder would look like a set icon, so an empty icon shows a muted symbol instead. */}
        {icon.length === 0 && (
          <SmilePlus className="pointer-events-none absolute top-3.5 left-3.5 size-5 text-muted-foreground" />
        )}
        <Input
          aria-label="Icon"
          className="size-12 border-transparent text-center text-3xl shadow-none hover:border-input"
          value={icon}
          onChange={(event) => setIcon(event.target.value)}
          onBlur={saveIcon}
          onKeyDown={(event) => event.key === 'Enter' && saveIcon()}
        />
      </div>
      <Input
        aria-label="Title"
        placeholder="Untitled"
        className="h-12 border-transparent text-3xl font-semibold shadow-none hover:border-input md:text-3xl"
        value={title}
        onChange={(event) => setTitle(event.target.value)}
        onBlur={saveTitle}
        onKeyDown={(event) => event.key === 'Enter' && saveTitle()}
      />
    </div>
  );
}
