import {
  flexRender,
  getCoreRowModel,
  getSortedRowModel,
  useReactTable,
  type CellContext,
  type ColumnDef,
  type HeaderContext,
  type RowData,
  type SortingState,
} from '@tanstack/react-table';
import { useVirtualizer } from '@tanstack/react-virtual';
import {
  ArrowDown,
  ArrowUp,
  ArrowUpRight,
  Inbox,
  LayoutGrid,
  Plus,
  Rows3,
  Search,
  SlidersHorizontal,
  Type,
} from 'lucide-react';
import { useMemo, useState, type ReactNode } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { useDbQuery } from '../../../core/database/use-db-query.ts';
import type { Attachment, Page } from '../../../core/database/schema.ts';
import { Button } from '../../../core/ui/button.tsx';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '../../../core/ui/table.tsx';
import { ToggleGroup, ToggleGroupItem } from '../../../core/ui/toggle-group.tsx';
import { isImage } from '../../files/data/attachments-repository.ts';
import { decodePageProperties } from '../../pages/data/pages-repository.ts';
import { EntryLookupDialog } from '../../plugins/widgets/entry-lookup-dialog.tsx';
import type { ResolvedField } from '../data/resolved-field.ts';
import { CollectionTilesView } from './collection-tiles-view.tsx';
import { FieldTypeIcon } from './field-type-icon.tsx';
import { FieldValueCell, InlineTextEditor } from './field-value-cell.tsx';

type Layout = 'table' | 'tiles';

const noTitles: ReadonlyMap<string, string> = new Map();
const noAttachments: AttachmentsByField = new Map();

/** Attachments of the files fields, by field id, then by entry id. */
type AttachmentsByField = ReadonlyMap<string, ReadonlyMap<string, Attachment[]>>;

/**
 * A collection's entries as a table or as tiles. Values are edited right in
 * the table and saved on commit; an entry opens as a page from its title.
 */
export function CollectionView(props: {
  collectionId: string;
  onEdit: () => void;
  onOpenEntry: (pageId: string) => void;
}) {
  const { collections, fields, fieldTypes, pages, attachments, plugins } = useAppServices();
  const lookup = plugins.templateOf(props.collectionId)?.lookup;
  const [lookingUp, setLookingUp] = useState(false);
  const { collectionId } = props;
  const [layout, setLayout] = useState<Layout>('table');
  // A state, not a ref: the views only measure their rows once it's there.
  const [scroller, setScroller] = useState<HTMLDivElement | null>(null);
  const { data: collection } = useDbQuery({
    tables: ['collections'],
    key: [collectionId],
    query: () => collections.byId(collectionId),
  });
  const { data: fieldRows = [] } = useDbQuery({
    tables: ['fields'],
    key: ['collection', collectionId],
    query: () => fields.listActiveInCollection(collectionId),
  });
  const { data: entries = [] } = useDbQuery({
    tables: ['pages'],
    key: ['collection', collectionId],
    query: () => pages.listActiveInCollection(collectionId),
  });
  const resolved = useMemo(() => fieldRows.map((row) => fieldTypes.resolve(row)), [fieldRows, fieldTypes]);

  // Relation cells show the related entries' titles, from whichever collections the relation fields target.
  const targets = [
    ...new Set(
      resolved.flatMap((field) =>
        field.typed.kind === 'relation' && field.typed.config.targetCollectionId !== undefined
          ? [field.typed.config.targetCollectionId]
          : [],
      ),
    ),
  ];
  const { data: relatedTitles = noTitles } = useDbQuery({
    tables: ['pages'],
    key: ['titles', ...targets],
    query: async () => {
      const related = await Promise.all(targets.map((target) => pages.listActiveInCollection(target)));
      return new Map(related.flat().map((page) => [page.id, page.title.length === 0 ? 'Untitled' : page.title]));
    },
  });

  const filesFields = resolved.filter((field) => field.typed.kind === 'files').map((field) => field.id);
  const { data: attachmentsByField = noAttachments } = useDbQuery({
    tables: ['attachments', 'pages'],
    key: ['collection', collectionId, ...filesFields],
    query: async (): Promise<AttachmentsByField> =>
      new Map(
        await Promise.all(
          filesFields.map(
            async (fieldId) => [fieldId, await attachments.listInFieldOfCollection(collectionId, fieldId)] as const,
          ),
        ),
      ),
  });

  async function addEntry() {
    if (collection === undefined) return;
    await pages.create({ spaceId: collection.space_id, collectionId });
  }

  const [firstField] = resolved;
  const coverField = resolved.find((field) => field.typed.kind === 'files');

  return (
    <div className="flex h-full flex-col gap-4 p-4 sm:p-6">
      {collection !== undefined && (
        <header className="flex items-center gap-3">
          {collection.icon !== null && <span className="text-3xl">{collection.icon}</span>}
          <div className="min-w-0">
            <h1 className="truncate text-2xl font-semibold">{collection.name}</h1>
            <p className="text-sm text-muted-foreground">
              {entries.length === 1 ? '1 entry' : `${entries.length} entries`}
            </p>
          </div>
        </header>
      )}
      <div className="flex items-center gap-2">
        <ToggleGroup
          type="single"
          variant="outline"
          size="sm"
          aria-label="Layout"
          value={layout}
          onValueChange={(value) => {
            if (value === 'table' || value === 'tiles') setLayout(value);
          }}
        >
          <ToggleGroupItem value="table" aria-label="Table">
            <Rows3 />
            <span className="hidden sm:inline">Table</span>
          </ToggleGroupItem>
          <ToggleGroupItem value="tiles" aria-label="Tiles">
            <LayoutGrid />
            <span className="hidden sm:inline">Tiles</span>
          </ToggleGroupItem>
        </ToggleGroup>
        <div className="flex-1" />
        <Button variant="ghost" onClick={props.onEdit}>
          <SlidersHorizontal />
          <span className="hidden sm:inline">Edit collection</span>
        </Button>
        {/* With a plugin's lookup, adding through it is the main action and a blank entry the secondary one. */}
        <Button variant={lookup === undefined ? 'default' : 'ghost'} onClick={() => void addEntry()}>
          <Plus />
          New entry
        </Button>
        {lookup !== undefined && (
          <Button onClick={() => setLookingUp(true)}>
            <Search />
            {lookup.actionLabel}
          </Button>
        )}
        {lookup !== undefined && lookingUp && (
          <EntryLookupDialog
            collectionId={props.collectionId}
            lookup={lookup}
            onOpenChange={setLookingUp}
            onOpenEntry={props.onOpenEntry}
          />
        )}
      </div>
      <div ref={setScroller} className="min-h-0 flex-1 overflow-auto">
        {entries.length === 0 ? (
          <EmptyState />
        ) : layout === 'table' ? (
          <EntriesTable
            titleLabel={collection?.title_field_label ?? 'Name'}
            fields={resolved}
            entries={entries}
            relatedTitles={relatedTitles}
            attachmentsByField={attachmentsByField}
            onOpenEntry={props.onOpenEntry}
            scroller={scroller}
          />
        ) : (
          <CollectionTilesView
            entries={entries.toSorted((a, b) => a.title.toLowerCase().localeCompare(b.title.toLowerCase()))}
            secondaryField={firstField}
            relatedTitles={relatedTitles}
            coverFor={
              coverField === undefined
                ? undefined
                : (entry) => attachmentsByField.get(coverField.id)?.get(entry.id)?.find(isImage)
            }
            onOpenEntry={props.onOpenEntry}
            scroller={scroller}
          />
        )}
      </div>
    </div>
  );
}

function EmptyState() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-1 p-6 text-center">
      <Inbox className="mb-2 size-9 text-muted-foreground" />
      <p className="text-lg font-medium">No entries yet</p>
      <p className="text-sm text-muted-foreground">Use "New entry" to add the first one.</p>
    </div>
  );
}

declare module '@tanstack/react-table' {
  // Type parameters must match TanStack's own declarations.
  // oxlint-disable-next-line typescript/no-unused-vars
  interface TableMeta<TData extends RowData> {
    titleLabel: string;
    relatedTitles: ReadonlyMap<string, string>;
    attachmentsByField: AttachmentsByField;
    onOpenEntry: (pageId: string) => void;
  }

  // oxlint-disable-next-line typescript/no-unused-vars
  interface ColumnMeta<TData extends RowData, TValue> {
    field?: ResolvedField;
  }
}

/** The built-in title column, then one per field - cells are fixed components, their context comes as `meta`. */
function columnsFor(fields: readonly ResolvedField[], relatedTitles: ReadonlyMap<string, string>): ColumnDef<Page>[] {
  return [
    {
      id: 'title',
      header: TitleHeader,
      accessorFn: (entry) => entry.title.toLowerCase(),
      size: 240,
      cell: TitleCell,
    },
    ...fields.map((field): ColumnDef<Page> => ({
      id: field.id,
      header: FieldHeader,
      // What sorting compares - numbers as numbers, everything else by its display text.
      accessorFn: (entry) => sortValueOf(field, decodePageProperties(entry.properties)[field.id], relatedTitles),
      size: columnWidthOf(field),
      enableSorting: field.typed.kind !== 'files',
      cell: ValueCell,
      meta: { field },
    })),
  ];
}

function TitleHeader({ table }: HeaderContext<Page, unknown>) {
  return <ColumnTitle icon={<Type />} title={table.options.meta?.titleLabel ?? 'Name'} />;
}

function FieldHeader({ column }: HeaderContext<Page, unknown>) {
  const field = column.columnDef.meta?.field;
  if (field === undefined) return null;
  return <ColumnTitle icon={<FieldTypeIcon base={field.base} variantId={field.variant?.id} />} title={field.name} />;
}

function TitleCell({ row, table }: CellContext<Page, unknown>) {
  const { pages } = useAppServices();
  const meta = table.options.meta;
  const entry = row.original;
  return (
    <div className="group flex items-center gap-1">
      <InlineTextEditor<string>
        label={meta?.titleLabel ?? 'Name'}
        value={entry.title}
        parse={(text) => ({ value: text.trim() })}
        onSave={(value) => pages.rename(entry.id, value)}
      >
        {entry.icon !== null && <span className="mr-1.5">{entry.icon}</span>}
        {entry.title.length === 0 ? (
          <span className="truncate text-muted-foreground">Untitled</span>
        ) : (
          <span className="truncate font-medium">{entry.title}</span>
        )}
      </InlineTextEditor>
      <Button
        variant="ghost"
        size="icon-xs"
        aria-label="Open"
        className="opacity-0 group-hover:opacity-100 focus-visible:opacity-100"
        onClick={() => meta?.onOpenEntry(entry.id)}
      >
        <ArrowUpRight />
      </Button>
    </div>
  );
}

function ValueCell({ row, column, table }: CellContext<Page, unknown>) {
  const field = column.columnDef.meta?.field;
  const meta = table.options.meta;
  if (field === undefined || meta === undefined) return null;
  return (
    <FieldValueCell
      entryId={row.original.id}
      field={field}
      raw={decodePageProperties(row.original.properties)[field.id]}
      relatedTitles={meta.relatedTitles}
      attachments={meta.attachmentsByField.get(field.id)?.get(row.original.id) ?? []}
    />
  );
}

/** A row's height before it's measured: the cells' h-11 and the border. */
const rowHeight = 45;

function EntriesTable(props: {
  titleLabel: string;
  fields: readonly ResolvedField[];
  entries: Page[];
  relatedTitles: ReadonlyMap<string, string>;
  attachmentsByField: AttachmentsByField;
  onOpenEntry: (pageId: string) => void;
  /** Scrolls the table - only the rows in and near its view are rendered. */
  scroller: HTMLElement | null;
}) {
  const [sorting, setSorting] = useState<SortingState>([]);
  const columns = useMemo(() => columnsFor(props.fields, props.relatedTitles), [props.fields, props.relatedTitles]);
  // A note for the React Compiler, which the app doesn't use - TanStack Table 8's API can't be memoized by it.
  // oxlint-disable-next-line react/incompatible-library
  const table = useReactTable({
    data: props.entries,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
    getRowId: (entry) => entry.id,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    meta: {
      titleLabel: props.titleLabel,
      relatedTitles: props.relatedTitles,
      attachmentsByField: props.attachmentsByField,
      onOpenEntry: props.onOpenEntry,
    },
  });

  const rows = table.getRowModel().rows;
  // oxlint-disable-next-line react/incompatible-library -- like useReactTable above
  const virtualizer = useVirtualizer({
    count: rows.length,
    getScrollElement: () => props.scroller,
    estimateSize: () => rowHeight,
    overscan: 10,
  });
  const visible = virtualizer.getVirtualItems();
  // Spacer rows stand in for the rows not rendered, so the scroll height stays the table's.
  const above = visible[0]?.start ?? 0;
  const below = virtualizer.getTotalSize() - (visible.at(-1)?.end ?? 0);

  return (
    <Table className="table-fixed rounded-lg border" style={{ width: table.getTotalSize() }}>
      <TableHeader className="bg-muted/60">
        {table.getHeaderGroups().map((group) => (
          <TableRow key={group.id}>
            {group.headers.map((header) => {
              const sorted = header.column.getIsSorted();
              return (
                <TableHead key={header.id} style={{ width: header.getSize() }} className="px-3">
                  <button
                    type="button"
                    disabled={!header.column.getCanSort()}
                    onClick={header.column.getToggleSortingHandler()}
                    className="flex w-full items-center gap-1 text-left"
                  >
                    {flexRender(header.column.columnDef.header, header.getContext())}
                    {sorted === 'asc' && <ArrowUp className="size-3.5" />}
                    {sorted === 'desc' && <ArrowDown className="size-3.5" />}
                  </button>
                </TableHead>
              );
            })}
          </TableRow>
        ))}
      </TableHeader>
      <TableBody>
        {above > 0 && <tr aria-hidden style={{ height: above }} />}
        {visible.map((item) => {
          const row = rows[item.index];
          return (
            row !== undefined && (
              <TableRow key={row.id} data-index={item.index} ref={virtualizer.measureElement}>
                {row.getVisibleCells().map((cell) => (
                  <TableCell key={cell.id} className="h-11 overflow-hidden px-3">
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </TableCell>
                ))}
              </TableRow>
            )
          );
        })}
        {below > 0 && <tr aria-hidden style={{ height: below }} />}
      </TableBody>
    </Table>
  );
}

function ColumnTitle({ icon, title }: { icon: ReactNode; title: string }) {
  return (
    <span className="flex min-w-0 items-center gap-1.5 text-[13px] font-medium text-muted-foreground [&_svg]:size-3.5 [&_svg]:shrink-0">
      {icon}
      <span className="truncate">{title}</span>
    </span>
  );
}

/** Narrower columns for values that are short by nature. */
function columnWidthOf(field: ResolvedField): number {
  switch (field.typed.kind) {
    case 'checkbox':
      return 110;
    case 'number':
    case 'date':
      return 150;
    default:
      return 200;
  }
}

function sortValueOf(field: ResolvedField, raw: unknown, relatedTitles: ReadonlyMap<string, string>): string | number {
  if (field.typed.kind === 'number' && field.errorFor(raw) === undefined) {
    const value = field.valueOf(raw);
    if (typeof value === 'number') return value;
  }
  if (field.typed.kind === 'relation' && Array.isArray(raw)) {
    return raw.map((id) => (typeof id === 'string' ? (relatedTitles.get(id) ?? '') : '')).join(', ');
  }
  return field.display(raw).toLowerCase();
}
