import type { Block } from '../../../core/database/schema.ts';

/**
 * A block as the editor holds it - the shape of BlockNote's blocks, kept
 * structural so the conversion and sync can be tested without the editor.
 */
export interface EditorBlock {
  readonly id: string;
  readonly type: string;
  readonly props: Readonly<Record<string, unknown>>;
  readonly content?: unknown;
  readonly children: readonly EditorBlock[];
}

/** What a block row's `content` column holds: the editor block without id, type and children. */
export function encodeBlockContent(block: Pick<EditorBlock, 'props' | 'content'>): string {
  return JSON.stringify(
    block.content === undefined ? { props: block.props } : { props: block.props, content: block.content },
  );
}

function decodeBlockContent(content: string): Pick<EditorBlock, 'props' | 'content'> {
  try {
    const json: unknown = JSON.parse(content);
    if (typeof json !== 'object' || json === null) return { props: {} };
    const props: unknown = Reflect.get(json, 'props');
    const inline: unknown = Reflect.get(json, 'content');
    return {
      props: typeof props === 'object' && props !== null ? { ...props } : {},
      ...(inline === undefined ? {} : { content: inline }),
    };
  } catch {
    return { props: {} };
  }
}

/**
 * Turns the flat block rows of a page - one row per block, so sync merges
 * per block - into the editor's tree, ordered by `position`. Each editor
 * block keeps its row's id; block-sync.ts relies on that to tell a changed
 * block from a new one.
 *
 * Blocks of a type the editor doesn't know (e.g. synced in by a newer app
 * version) are left out, together with their children - and left alone by
 * the sync, so they aren't lost.
 */
export function buildDocument(blocks: readonly Block[], knownTypes: ReadonlySet<string>): EditorBlock[] {
  const byParent = new Map<string | null, Block[]>();
  for (const block of blocks) {
    byParent.set(block.parent_block_id, [...(byParent.get(block.parent_block_id) ?? []), block]);
  }
  const build = (parentId: string | null): EditorBlock[] =>
    (byParent.get(parentId) ?? [])
      .toSorted((a, b) => a.position - b.position || a.id.localeCompare(b.id))
      .filter((block) => knownTypes.has(block.type))
      .map((block) => ({
        id: block.id,
        type: block.type,
        ...decodeBlockContent(block.content),
        children: build(block.id),
      }));
  return build(null);
}

/** The ids of blocks {@link buildDocument} leaves out - the sync must not delete them. */
export function hiddenBlockIds(blocks: readonly Block[], knownTypes: ReadonlySet<string>): Set<string> {
  const hidden = new Set(blocks.filter((block) => !knownTypes.has(block.type)).map((block) => block.id));
  let grew = true;
  while (grew) {
    grew = false;
    for (const block of blocks) {
      if (!hidden.has(block.id) && block.parent_block_id !== null && hidden.has(block.parent_block_id)) {
        hidden.add(block.id);
        grew = true;
      }
    }
  }
  return hidden;
}
