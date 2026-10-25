import * as v from 'valibot';

import { encodeBlockContent } from '../../pages/widgets/block-document.ts';
import { attachmentBlockType, attachmentIdProp } from '../../pages/widgets/block-sync.ts';

/** A block row's `type` and `content` as the TypeScript app stores them (see block-document.ts). */
export interface ConvertedBlock {
  readonly type: string;
  readonly content: string;
}

/** BlockNote's inline content: styled text, and links holding styled text. */
type InlineContent =
  | { type: 'text'; text: string; styles: Record<string, true> }
  | { type: 'link'; href: string; content: { type: 'text'; text: string; styles: Record<string, true> }[] };

const deltaSchema = v.array(
  v.object({
    insert: v.unknown(),
    attributes: v.optional(v.record(v.string(), v.unknown())),
  }),
);

/** AppFlowy's delta attributes that BlockNote has a style for - colors are left behind. */
const styleOf: Readonly<Record<string, string>> = {
  bold: 'bold',
  italic: 'italic',
  underline: 'underline',
  strikethrough: 'strike',
  code: 'code',
};

const colorProps = { backgroundColor: 'default', textColor: 'default', textAlignment: 'left' } as const;

/**
 * Translates one block of the Flutter app's editor (AppFlowy: its node
 * type and attributes) into a BlockNote block. The common text blocks map
 * directly, with bold, italic, underline, strikethrough, code and links;
 * anything else becomes a paragraph with its plain text, so no text is lost.
 */
export function blockFromAppFlowy(type: string, content: string): ConvertedBlock {
  const attributes = parseObject(content);
  const inline = inlineOf(attributes['delta']);
  const block = (blockType: string, props: Record<string, unknown>, withText = true): ConvertedBlock => ({
    type: blockType,
    content: encodeBlockContent(withText ? { props, content: inline } : { props }),
  });
  switch (type) {
    case 'paragraph':
      return block('paragraph', colorProps);
    case 'heading': {
      const level = attributes['level'];
      return block('heading', {
        ...colorProps,
        level: typeof level === 'number' ? Math.min(Math.max(Math.round(level), 1), 6) : 1,
        isToggleable: false,
      });
    }
    case 'bulleted_list':
      return block('bulletListItem', colorProps);
    case 'numbered_list':
      return block('numberedListItem', colorProps);
    case 'todo_list':
      return block('checkListItem', { ...colorProps, checked: attributes['checked'] === true });
    case 'quote':
      return block('quote', { backgroundColor: 'default', textColor: 'default' });
    case 'code': {
      const language = attributes['language'];
      return {
        type: 'codeBlock',
        content: encodeBlockContent({
          props: { language: typeof language === 'string' ? language : 'text' },
          content: [{ type: 'text', text: plainText(inline), styles: {} }],
        }),
      };
    }
    case 'divider':
      return block('divider', {}, false);
    case attachmentBlockType: {
      const id = attributes[attachmentIdProp];
      return block(attachmentBlockType, { [attachmentIdProp]: typeof id === 'string' ? id : '' }, false);
    }
    case 'image': {
      // A picture by URL, not a file of the app - kept as a link to it.
      const url = attributes['url'];
      if (typeof url === 'string' && url.length > 0) {
        return {
          type: 'paragraph',
          content: encodeBlockContent({
            props: colorProps,
            content: [{ type: 'link', href: url, content: [{ type: 'text', text: url, styles: {} }] }],
          }),
        };
      }
      return block('paragraph', colorProps);
    }
    default:
      return {
        type: 'paragraph',
        content: encodeBlockContent({ props: colorProps, content: plainOnly(inline) }),
      };
  }
}

function parseObject(content: string): Record<string, unknown> {
  try {
    const json: unknown = JSON.parse(content);
    return typeof json === 'object' && json !== null && !Array.isArray(json) ? { ...json } : {};
  } catch {
    return {};
  }
}

/** A delta's text inserts as BlockNote inline content; embeds (non-text inserts) are skipped. */
function inlineOf(delta: unknown): InlineContent[] {
  const parsed = v.safeParse(deltaSchema, delta);
  if (!parsed.success) return [];
  return parsed.output.flatMap((op): InlineContent[] => {
    if (typeof op.insert !== 'string' || op.insert.length === 0) return [];
    const styles: Record<string, true> = {};
    for (const [attribute, value] of Object.entries(op.attributes ?? {})) {
      const style = styleOf[attribute];
      if (style !== undefined && value === true) styles[style] = true;
    }
    const text = { type: 'text' as const, text: op.insert, styles };
    const href = op.attributes?.['href'];
    return [typeof href === 'string' && href.length > 0 ? { type: 'link', href, content: [text] } : text];
  });
}

function plainText(inline: readonly InlineContent[]): string {
  return inline
    .map((item) => (item.type === 'text' ? item.text : item.content.map((part) => part.text).join('')))
    .join('');
}

function plainOnly(inline: readonly InlineContent[]): InlineContent[] {
  const text = plainText(inline);
  return text.length === 0 ? [] : [{ type: 'text', text, styles: {} }];
}
