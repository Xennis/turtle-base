import { useVirtualizer } from '@tanstack/react-virtual';
import { useEffect, useState } from 'react';

import type { Attachment, Page } from '../../../core/database/schema.ts';
import { Card } from '../../../core/ui/card.tsx';
import { AttachmentCover } from '../../files/widgets/attachment-thumbnail.tsx';
import { decodePageProperties } from '../../pages/data/pages-repository.ts';
import type { ResolvedField } from '../data/resolved-field.ts';
import { resolveSelectValue } from '../data/select-field.ts';
import { SelectOptionChip } from './select-option-chip.tsx';

/** A tile's least width, and the gap between tiles (gap-3) - as many columns as fit. */
const minTileWidth = 220;
const tileGap = 12;

/**
 * The entries as cards: title, below it the value of the collection's first
 * field (select values as chips), and - with `coverFor` - a cover from the
 * first files field. Laid out in rows of as many tiles as fit; only the rows
 * in and near `scroller`'s view are rendered.
 */
export function CollectionTilesView(props: {
  entries: readonly Page[];
  secondaryField: ResolvedField | undefined;
  relatedTitles: ReadonlyMap<string, string>;
  coverFor: ((entry: Page) => Attachment | undefined) | undefined;
  onOpenEntry: (pageId: string) => void;
  scroller: HTMLElement | null;
}) {
  const [container, setContainer] = useState<HTMLDivElement | null>(null);
  const [width, setWidth] = useState(0);

  useEffect(() => {
    if (container === null) return;
    const observer = new ResizeObserver(([entry]) => setWidth(entry?.contentRect.width ?? 0));
    observer.observe(container);
    return () => observer.disconnect();
  }, [container]);

  const columns = Math.max(1, Math.floor((width + tileGap) / (minTileWidth + tileGap)));
  const rows: (readonly Page[])[] = [];
  for (let start = 0; start < props.entries.length; start += columns) {
    rows.push(props.entries.slice(start, start + columns));
  }
  // oxlint-disable-next-line react/incompatible-library -- TanStack Virtual's API can't be memoized by the React Compiler
  const virtualizer = useVirtualizer({
    count: rows.length,
    getScrollElement: () => props.scroller,
    // Measured once rendered - tiles with a cover are taller.
    estimateSize: () => (props.coverFor === undefined ? 110 : 230),
    gap: tileGap,
    overscan: 3,
  });

  return (
    <div ref={setContainer} className="relative" style={{ height: virtualizer.getTotalSize() }}>
      {virtualizer.getVirtualItems().map((item) => (
        <div
          key={item.key}
          data-index={item.index}
          ref={virtualizer.measureElement}
          className="absolute inset-x-0 top-0 grid gap-3"
          style={{
            transform: `translateY(${item.start}px)`,
            gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))`,
          }}
        >
          {(rows[item.index] ?? []).map((entry) => (
            <Tile key={entry.id} entry={entry} {...props} />
          ))}
        </div>
      ))}
    </div>
  );
}

function Tile(props: {
  entry: Page;
  secondaryField: ResolvedField | undefined;
  relatedTitles: ReadonlyMap<string, string>;
  coverFor: ((entry: Page) => Attachment | undefined) | undefined;
  onOpenEntry: (pageId: string) => void;
}) {
  const { entry } = props;
  return (
    <Card
      role="button"
      tabIndex={0}
      aria-label={entry.title.length === 0 ? 'Untitled' : entry.title}
      onClick={() => props.onOpenEntry(entry.id)}
      onKeyDown={(event) => {
        if (event.key === 'Enter') props.onOpenEntry(entry.id);
      }}
      className="cursor-pointer gap-0 overflow-hidden py-0 hover:ring-2 hover:ring-ring"
    >
      {props.coverFor !== undefined && (
        <div className="h-30">
          <AttachmentCover attachment={props.coverFor(entry)} />
        </div>
      )}
      <div className="grid gap-2 p-4">
        <div className="flex items-center gap-2">
          {entry.icon !== null && <span className="text-xl">{entry.icon}</span>}
          <span className="line-clamp-2 text-base font-medium">
            {entry.title.length === 0 ? 'Untitled' : entry.title}
          </span>
        </div>
        <Secondary field={props.secondaryField} entry={entry} relatedTitles={props.relatedTitles} />
      </div>
    </Card>
  );
}

function Secondary(props: {
  field: ResolvedField | undefined;
  entry: Page;
  relatedTitles: ReadonlyMap<string, string>;
}) {
  const { field } = props;
  if (field === undefined) return null;
  const raw = decodePageProperties(props.entry.properties)[field.id];
  if (field.typed.kind === 'select' || field.typed.kind === 'multiSelect') {
    const selected = resolveSelectValue(field.typed.config.options, field.valueOf(raw));
    if (selected.length === 0) return null;
    return (
      <div className="flex flex-wrap gap-1">
        {selected.map((option) => (
          <SelectOptionChip key={option.id} option={option} />
        ))}
      </div>
    );
  }
  const text =
    field.typed.kind === 'relation' && Array.isArray(raw)
      ? raw.map((id) => (typeof id === 'string' ? (props.relatedTitles.get(id) ?? '?') : '?')).join(', ')
      : field.display(raw);
  if (text.length === 0) return null;
  return <p className="truncate text-sm text-muted-foreground">{text}</p>;
}
