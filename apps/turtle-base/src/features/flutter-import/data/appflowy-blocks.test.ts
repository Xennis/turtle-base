import { describe, expect, test } from 'vite-plus/test';

import { blockFromAppFlowy } from './appflowy-blocks.ts';

function converted(type: string, attributes: unknown) {
  const block = blockFromAppFlowy(type, JSON.stringify(attributes));
  const stored: unknown = JSON.parse(block.content);
  return { type: block.type, ...(typeof stored === 'object' ? stored : {}) };
}

describe('blockFromAppFlowy', () => {
  test('keeps text styles and links', () => {
    expect(
      converted('paragraph', {
        delta: [
          { insert: 'plain ' },
          { insert: 'bold', attributes: { bold: true, font_color: '0xff0000' } },
          { insert: ' gone', attributes: { strikethrough: true, italic: true } },
          { insert: 'site', attributes: { href: 'https://example.com', underline: true } },
        ],
      }),
    ).toEqual({
      type: 'paragraph',
      props: { backgroundColor: 'default', textColor: 'default', textAlignment: 'left' },
      content: [
        { type: 'text', text: 'plain ', styles: {} },
        { type: 'text', text: 'bold', styles: { bold: true } },
        { type: 'text', text: ' gone', styles: { strike: true, italic: true } },
        {
          type: 'link',
          href: 'https://example.com',
          content: [{ type: 'text', text: 'site', styles: { underline: true } }],
        },
      ],
    });
  });

  test('maps the list, heading and check blocks to their BlockNote types', () => {
    expect(converted('heading', { delta: [{ insert: 'Title' }], level: 2 })).toMatchObject({
      type: 'heading',
      props: { level: 2, isToggleable: false },
      content: [{ text: 'Title' }],
    });
    expect(converted('heading', { delta: [], level: 9 })).toMatchObject({ props: { level: 6 } });
    expect(converted('bulleted_list', { delta: [{ insert: 'a' }] }).type).toBe('bulletListItem');
    expect(converted('numbered_list', { delta: [{ insert: 'b' }], number: 3 }).type).toBe('numberedListItem');
    expect(converted('todo_list', { delta: [{ insert: 'c' }], checked: true })).toMatchObject({
      type: 'checkListItem',
      props: { checked: true },
    });
    expect(converted('quote', { delta: [{ insert: 'd' }] }).type).toBe('quote');
  });

  test('keeps attachments and dividers, without text', () => {
    expect(converted('attachment', { attachmentId: 'att-1' })).toEqual({
      type: 'attachment',
      props: { attachmentId: 'att-1' },
    });
    expect(converted('divider', {})).toEqual({ type: 'divider', props: {} });
  });

  test('turns a picture by URL into a link to it', () => {
    expect(converted('image', { url: 'https://example.com/a.png' })).toMatchObject({
      type: 'paragraph',
      content: [{ type: 'link', href: 'https://example.com/a.png' }],
    });
  });

  test('turns anything else into a paragraph with its plain text', () => {
    expect(
      converted('callout', { delta: [{ insert: 'Note ', attributes: { bold: true } }, { insert: { mention: 'x' } }] }),
    ).toMatchObject({ type: 'paragraph', content: [{ type: 'text', text: 'Note ', styles: {} }] });
    expect(converted('table', { colsLen: 2 })).toMatchObject({ type: 'paragraph', content: [] });
    expect(blockFromAppFlowy('paragraph', 'not json').type).toBe('paragraph');
  });
});
