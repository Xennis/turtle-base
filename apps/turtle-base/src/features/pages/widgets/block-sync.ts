import type { Block } from '../../../core/database/schema.ts';
import type { AttachmentsRepository } from '../../files/data/attachments-repository.ts';
import type { BlocksRepository } from '../data/blocks-repository.ts';
import { encodeBlockContent, type EditorBlock } from './block-document.ts';

/**
 * Writes the editor's tree back into the page's flat block rows - the
 * reverse of buildDocument. A block keeps its row's id, so it's told apart
 * by id alone: an existing block (maybe changed, moved or re-typed), a new
 * one (an id not stored yet, e.g. after pressing Enter), or one the user
 * removed (stored, but no longer in the tree - soft-deleted). Rows in
 * `untouched` (blocks the editor doesn't show) are left as they are.
 */
export async function syncBlocksFromDocument(options: {
  blocks: BlocksRepository;
  pageId: string;
  document: readonly EditorBlock[];
  currentBlocks: readonly Block[];
  untouched?: ReadonlySet<string>;
}): Promise<void> {
  const { blocks, pageId } = options;
  const current = new Map(options.currentBlocks.map((block) => [block.id, block]));
  const seen = new Set<string>();

  async function walk(nodes: readonly EditorBlock[], parentId: string | null): Promise<void> {
    for (const [position, node] of nodes.entries()) {
      seen.add(node.id);
      const content = encodeBlockContent(node);
      const existing = current.get(node.id);
      if (existing === undefined) {
        await blocks.create({ id: node.id, pageId, parentBlockId: parentId, type: node.type, content });
        await blocks.move(node.id, parentId, position);
      } else {
        if (existing.type !== node.type) await blocks.changeType(node.id, node.type);
        if (existing.content !== content) await blocks.updateContent(node.id, content);
        if (existing.parent_block_id !== parentId || existing.position !== position) {
          await blocks.move(node.id, parentId, position);
        }
      }
      await walk(node.children, node.id);
    }
  }

  await walk(options.document, null);
  for (const block of options.currentBlocks) {
    if (!seen.has(block.id) && options.untouched?.has(block.id) !== true) await blocks.softDelete(block.id);
  }
}

/** The type of the editor block showing an attachment of the page's text, and its prop holding the attachment's id. */
export const attachmentBlockType = 'attachment';
export const attachmentIdProp = 'attachmentId';

/**
 * Keeps the page's text attachments (those without a field) in step with the
 * attachment blocks in `document`: an attachment is active exactly while a
 * block references it - removing the block soft-deletes it, undoing that
 * restores it.
 *
 * A block referencing another page's attachment (pasted from there) gets a
 * copy of its own, so the two pages don't share one row. Returns those
 * replacements, old id to new, for the caller to write into the blocks.
 */
export async function syncAttachmentsFromDocument(options: {
  attachments: AttachmentsRepository;
  pageId: string;
  document: readonly EditorBlock[];
}): Promise<Map<string, string>> {
  const { attachments, pageId } = options;
  const referenced = new Set<string>();
  const walk = (nodes: readonly EditorBlock[]) => {
    for (const node of nodes) {
      const id = node.props[attachmentIdProp];
      if (node.type === attachmentBlockType && typeof id === 'string' && id.length > 0) referenced.add(id);
      walk(node.children);
    }
  };
  walk(options.document);

  const own = new Map((await attachments.allInPageContent(pageId)).map((attachment) => [attachment.id, attachment]));
  const replacements = new Map<string, string>();
  for (const id of referenced) {
    const attachment = own.get(id);
    if (attachment !== undefined) {
      if (attachment.deleted_at !== null) await attachments.restore(id);
      continue;
    }
    // Unknown here - another page's, or not synced in yet (then it's left alone).
    const foreign = await attachments.byId(id);
    if (foreign !== undefined) replacements.set(id, await attachments.copyTo(foreign, pageId));
  }
  for (const attachment of own.values()) {
    if (attachment.deleted_at === null && !referenced.has(attachment.id)) await attachments.softDelete(attachment.id);
  }
  return replacements;
}
