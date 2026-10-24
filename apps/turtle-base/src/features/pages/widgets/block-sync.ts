import type { Block } from '../../../core/database/schema.ts';
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
