import { Plus, X } from 'lucide-react';
import { useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { useDbQuery } from '../../../core/database/use-db-query.ts';
import type { Page } from '../../../core/database/schema.ts';
import { Button } from '../../../core/ui/button.tsx';
import { decodeRelationValue } from '../../tables/data/relation-field.ts';
import type { ResolvedField } from '../../tables/data/resolved-field.ts';
import { FieldTypeIcon } from '../../tables/widgets/field-type-icon.tsx';
import { FieldValueCell } from '../../tables/widgets/field-value-cell.tsx';
import { decodePageProperties } from '../data/pages-repository.ts';
import { RelationPickerDialog } from './relation-picker-dialog.tsx';

/**
 * A collection entry's field values above its text - edited like in the
 * table, plus relations, which are picked here.
 */
export function PagePropertiesHeader({ page, collectionId }: { page: Page; collectionId: string }) {
  const { fields, fieldTypes, attachments } = useAppServices();
  const { data: rows = [] } = useDbQuery({
    tables: ['fields'],
    key: ['collection', collectionId],
    query: () => fields.listActiveInCollection(collectionId),
  });
  const { data: pageAttachments = [] } = useDbQuery({
    tables: ['attachments'],
    key: ['page', page.id, ...rows.map((row) => row.id)],
    query: () => Promise.all(rows.map((row) => attachments.listInField(page.id, row.id))),
  });
  if (rows.length === 0) return null;
  const properties = decodePageProperties(page.properties);

  return (
    <dl className="grid grid-cols-[minmax(0,10rem)_minmax(0,1fr)] items-center gap-x-4 gap-y-1">
      {rows.map((row, index) => {
        const field = fieldTypes.resolve(row);
        return (
          <div key={field.id} className="contents">
            <dt className="flex min-w-0 items-center gap-2 text-sm text-muted-foreground [&_svg]:size-4 [&_svg]:shrink-0">
              <FieldTypeIcon base={field.base} variantId={field.variant?.id} />
              <span className="truncate">{field.name}</span>
            </dt>
            <dd className="flex min-h-8 min-w-0 items-center text-sm">
              {field.typed.kind === 'relation' ? (
                <RelationValue page={page} field={field} raw={properties[field.id]} />
              ) : (
                <FieldValueCell
                  entryId={page.id}
                  field={field}
                  raw={properties[field.id]}
                  attachments={pageAttachments[index] ?? []}
                  placeholder="Empty"
                />
              )}
            </dd>
          </div>
        );
      })}
    </dl>
  );
}

function RelationValue({ page, field, raw }: { page: Page; field: ResolvedField; raw: unknown }) {
  const { pages } = useAppServices();
  const [picking, setPicking] = useState(false);
  const target = field.typed.kind === 'relation' ? field.typed.config.targetCollectionId : undefined;
  const ids = decodeRelationValue(raw);
  const { data: titles = new Map<string, string>() } = useDbQuery({
    tables: ['pages'],
    key: ['titles', target],
    query: async () =>
      new Map(
        (target === undefined ? [] : await pages.listActiveInCollection(target)).map((entry) => [
          entry.id,
          entry.title.length === 0 ? 'Untitled' : entry.title,
        ]),
      ),
  });
  if (target === undefined) return <span className="text-muted-foreground">No target collection configured</span>;
  const save = (next: readonly string[]) => pages.setPropertyValue(page.id, field.id, next);

  return (
    <div className="flex flex-wrap items-center gap-1">
      {ids.flatMap((id) => {
        const title = titles.get(id);
        // Related entries deleted since aren't shown.
        if (title === undefined) return [];
        return [
          <span
            key={id}
            className="inline-flex items-center gap-0.5 rounded-full bg-secondary py-0.5 pr-1 pl-2.5 text-xs"
          >
            {title}
            <button
              type="button"
              aria-label={`Remove ${title}`}
              className="rounded-full p-0.5"
              onClick={() => void save(ids.filter((other) => other !== id))}
            >
              <X className="size-3" />
            </button>
          </span>,
        ];
      })}
      <Button variant="ghost" size="xs" onClick={() => setPicking(true)}>
        <Plus />
        Add
      </Button>
      {picking && (
        <RelationPickerDialog targetCollectionId={target} selectedIds={ids} onOpenChange={setPicking} onPick={save} />
      )}
    </div>
  );
}
