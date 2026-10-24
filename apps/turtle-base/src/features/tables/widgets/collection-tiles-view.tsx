import type { Attachment, Page } from '../../../core/database/schema.ts';
import { Card } from '../../../core/ui/card.tsx';
import { AttachmentCover } from '../../files/widgets/attachment-thumbnail.tsx';
import { decodePageProperties } from '../../pages/data/pages-repository.ts';
import type { ResolvedField } from '../data/resolved-field.ts';
import { resolveSelectValue } from '../data/select-field.ts';
import { SelectOptionChip } from './select-option-chip.tsx';

/**
 * The entries as cards: title, below it the value of the collection's first
 * field (select values as chips), and - with `coverFor` - a cover from the
 * first files field.
 */
export function CollectionTilesView(props: {
  entries: readonly Page[];
  secondaryField: ResolvedField | undefined;
  relatedTitles: ReadonlyMap<string, string>;
  coverFor: ((entry: Page) => Attachment | undefined) | undefined;
  onOpenEntry: (pageId: string) => void;
}) {
  return (
    <div className="grid grid-cols-[repeat(auto-fill,minmax(220px,1fr))] gap-3">
      {props.entries.map((entry) => (
        <Card
          key={entry.id}
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
      ))}
    </div>
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
