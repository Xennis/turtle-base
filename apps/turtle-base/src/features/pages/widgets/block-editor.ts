/* oxlint-disable typescript/no-explicit-any, typescript/no-unsafe-type-assertion, typescript/no-unsafe-argument, typescript/no-unsafe-assignment, typescript/no-unsafe-return, typescript/no-unsafe-member-access, typescript/no-unsafe-call --
 * BlockNote's generic block types don't satisfy their own constraints under exactOptionalPropertyTypes, so the
 * editor is driven untyped here - and only here: the page talks to it through BlockEditor, in terms of
 * EditorBlock. BlockNote checks the blocks against its schema at runtime.
 */
import { BlockNoteSchema, defaultBlockSpecs, type BlockNoteEditor, type BlockSpecs } from '@blocknote/core';

import { attachmentBlock } from '../../files/widgets/attachment-block.tsx';

import type { EditorBlock } from './block-document.ts';

// BlockNote's own media blocks store URLs; files are attachments here, kept in the file store and synced.
const { image: _image, video: _video, audio: _audio, file: _file, ...textBlockSpecs } = defaultBlockSpecs;

/** The blocks a page's text is made of: BlockNote's text blocks and the attachment block. */
export const pageSchema = BlockNoteSchema.create({
  blockSpecs: { ...textBlockSpecs, attachment: attachmentBlock() } as unknown as BlockSpecs,
});

/** A block to insert - the editor fills in the id, the remaining props and the children. */
export interface NewBlock {
  readonly type: string;
  readonly props: Readonly<Record<string, string | number | boolean>>;
}

/** The few operations the page needs from the block editor. */
export interface BlockEditor {
  readonly document: () => EditorBlock[];
  readonly isFocused: () => boolean;
  /** The block the text cursor is in. */
  readonly cursorBlockId: () => string | undefined;
  /** Replaces the whole content, e.g. with blocks stored meanwhile. */
  readonly replaceAll: (blocks: readonly EditorBlock[]) => void;
  /** Inserts after `referenceId`, or at the end - replacing an empty paragraph rather than leaving it. */
  readonly insertAfter: (blocks: readonly NewBlock[], referenceId: string | undefined) => void;
  readonly setProps: (blockId: string, props: Readonly<Record<string, string>>) => void;
}

export function blockEditorOf(editor: BlockNoteEditor<any, any, any>): BlockEditor {
  const document = () => editor.document as EditorBlock[];
  return {
    document,
    isFocused: () => editor.isFocused(),
    cursorBlockId: () => (editor.isFocused() ? editor.getTextCursorPosition().block.id : undefined),
    replaceAll: (blocks) => {
      editor.replaceBlocks(editor.document, blocks as any[]);
    },
    insertAfter: (blocks, referenceId) => {
      const reference = referenceId ?? document().at(-1)?.id;
      if (blocks.length === 0 || reference === undefined) return;
      const block = editor.getBlock(reference);
      const isEmptyParagraph =
        block?.type === 'paragraph' && Array.isArray(block.content) && block.content.length === 0;
      if (isEmptyParagraph) editor.replaceBlocks([reference], blocks as any[]);
      else editor.insertBlocks(blocks as any[], reference, 'after');
    },
    setProps: (blockId, props) => {
      editor.updateBlock(blockId, { props } as any);
    },
  };
}
