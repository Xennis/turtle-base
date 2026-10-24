import { GripVertical, Plus, SlidersHorizontal, Trash2 } from 'lucide-react';
import { useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { useDbQuery } from '../../../core/database/use-db-query.ts';
import type { Collection } from '../../../core/database/schema.ts';
import { Button } from '../../../core/ui/button.tsx';
import { Input } from '../../../core/ui/input.tsx';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../../../core/ui/select.tsx';
import { textFieldType } from '../data/base-field-type.ts';
import { conversionMode, type TypeChangePlan } from '../data/field-conversion.ts';
import { FieldTypeChoice } from '../data/field-type-registry.ts';
import { encodeRelationConfig } from '../data/relation-field.ts';
import type { ResolvedField } from '../data/resolved-field.ts';
import { encodeSelectConfig } from '../data/select-field.ts';
import { FieldConfigEditor } from './field-config-editor.tsx';
import { FieldTypeIcon } from './field-type-icon.tsx';
import { FieldTypePicker } from './field-type-picker.tsx';
import { SelectOptionsEditor } from './select-options-editor.tsx';
import { needsTypeChangeConfirmation, TypeChangeDialog } from './type-change-dialog.tsx';

/**
 * The "Fields" part of the collection edit page: one compact row per field -
 * drag (or arrow keys on the handle) to reorder - whose type-specific
 * settings fold out below it, plus a row to add a field.
 */
export function FieldsEditor({ collectionId, spaceId }: { collectionId: string; spaceId: string }) {
  const { fields, collections, fieldTypes } = useAppServices();
  const { data: rows = [] } = useDbQuery({
    tables: ['fields'],
    key: ['collection', collectionId],
    query: () => fields.listActiveInCollection(collectionId),
  });
  // The relation type's target picker offers the space's collections.
  const { data: spaceCollections = [] } = useDbQuery({
    tables: ['collections'],
    key: [spaceId],
    query: () => collections.listActiveInSpace(spaceId),
  });
  const [expanded, setExpanded] = useState<ReadonlySet<string>>(new Set());
  const [dragged, setDragged] = useState<number | undefined>();
  const resolved = rows.map((row) => fieldTypes.resolve(row));

  function move(from: number, to: number) {
    if (to < 0 || to >= rows.length || from === to) return;
    const ids = rows.map((row) => row.id);
    const [id] = ids.splice(from, 1);
    if (id === undefined) return;
    ids.splice(to, 0, id);
    void fields.reorderAll(ids);
  }

  function toggle(id: string, open: boolean) {
    setExpanded((ids) => {
      const next = new Set(ids);
      if (open) next.add(id);
      else next.delete(id);
      return next;
    });
  }

  return (
    <div className="grid gap-1">
      {resolved.length === 0 && (
        <p className="py-3 text-sm text-muted-foreground">
          No fields yet - add one below to give each entry more than a name.
        </p>
      )}
      {resolved.map((field, index) => (
        <div
          key={field.id}
          onDragOver={(event) => dragged !== undefined && event.preventDefault()}
          onDrop={() => {
            if (dragged !== undefined) move(dragged, index);
            setDragged(undefined);
          }}
          className={dragged === index ? 'opacity-50' : undefined}
        >
          <FieldRow
            field={field}
            collections={spaceCollections}
            expanded={expanded.has(field.id)}
            onExpandedChange={(open) => toggle(field.id, open)}
            onDragStart={() => setDragged(index)}
            onDragEnd={() => setDragged(undefined)}
            onMove={(by) => move(index, index + by)}
          />
        </div>
      ))}
      <AddFieldRow
        collectionId={collectionId}
        collections={spaceCollections}
        // Straight to a new select's settings, to add its options.
        onAdded={(id, isSelect) => isSelect && toggle(id, true)}
      />
    </div>
  );
}

/** Whether `field` has settings to fold out - variants have none, see FieldConfigEditor. */
function hasSettings(field: ResolvedField): boolean {
  if (field.variant !== undefined) return false;
  switch (field.typed.kind) {
    case 'text':
    case 'number':
    case 'select':
    case 'multiSelect':
    case 'relation':
    case 'files':
      return true;
    default:
      return false;
  }
}

function FieldRow(props: {
  field: ResolvedField;
  collections: readonly Collection[];
  expanded: boolean;
  onExpandedChange: (open: boolean) => void;
  onDragStart: () => void;
  onDragEnd: () => void;
  onMove: (by: -1 | 1) => void;
}) {
  const { fields, fieldTypes } = useAppServices();
  const { field } = props;
  const [name, setName] = useState(field.name);
  const [pending, setPending] = useState<{ plan: TypeChangePlan; label: string } | undefined>();
  const current = new FieldTypeChoice(field.base, field.variant);
  const choices = fieldTypes.choices.filter(
    (choice) => choice.key === current.key || conversionMode(field.base, choice.base) !== 'none',
  );
  const missingTarget = field.typed.kind === 'relation' && field.typed.config.targetCollectionId === undefined;
  const settingsShown = hasSettings(field) && (props.expanded || missingTarget);

  function saveName() {
    const trimmed = name.trim();
    if (trimmed.length > 0 && trimmed !== field.name) void fields.rename(field.id, trimmed);
  }

  async function changeType(choice: FieldTypeChoice) {
    const plan = await fields.planTypeChange(field.id, choice);
    if (needsTypeChangeConfirmation(plan)) setPending({ plan, label: choice.label });
    else await fields.applyTypeChange(plan);
  }

  return (
    <div className="py-1">
      <div className="flex flex-wrap items-center gap-1 sm:flex-nowrap">
        <button
          type="button"
          draggable
          aria-label={`Move ${field.name} (arrow keys)`}
          onDragStart={props.onDragStart}
          onDragEnd={props.onDragEnd}
          onKeyDown={(event) => {
            if (event.key === 'ArrowUp') props.onMove(-1);
            if (event.key === 'ArrowDown') props.onMove(1);
          }}
          className="cursor-grab rounded p-1 text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring"
        >
          <GripVertical className="size-4" />
        </button>
        <div className="relative min-w-0 flex-1 [&_svg]:pointer-events-none [&_svg]:absolute [&_svg]:top-2 [&_svg]:left-2.5 [&_svg]:size-4 [&_svg]:text-muted-foreground">
          <FieldTypeIcon base={field.base} variantId={field.variant?.id} />
          <Input
            aria-label="Field name"
            className="pl-8"
            value={name}
            onChange={(event) => setName(event.target.value)}
            onBlur={saveName}
            onKeyDown={(event) => event.key === 'Enter' && saveName()}
          />
        </div>
        <FieldTypePicker
          // Remounted after a cancelled change, which already showed the picked type.
          key={pending === undefined ? current.key : 'pending'}
          value={current}
          choices={choices}
          onChange={(choice) => void changeType(choice)}
        />
        <Button
          variant="ghost"
          size="icon"
          aria-label={settingsShown ? 'Hide field settings' : 'Field settings'}
          aria-pressed={settingsShown}
          className={hasSettings(field) ? 'aria-pressed:bg-muted' : 'invisible'}
          onClick={() => props.onExpandedChange(!props.expanded)}
        >
          <SlidersHorizontal />
        </Button>
        <Button variant="ghost" size="icon" aria-label="Delete field" onClick={() => void fields.softDelete(field.id)}>
          <Trash2 />
        </Button>
      </div>
      {settingsShown && (
        <div className="mt-2 ml-7 rounded-lg bg-muted/50 p-3">
          <FieldSettings field={field} collections={props.collections} />
        </div>
      )}
      {pending !== undefined && (
        <TypeChangeDialog
          plan={pending.plan}
          typeLabel={pending.label}
          onCancel={() => setPending(undefined)}
          onConfirm={async () => {
            await fields.applyTypeChange(pending.plan);
            setPending(undefined);
          }}
        />
      )}
    </div>
  );
}

function FieldSettings({ field, collections }: { field: ResolvedField; collections: readonly Collection[] }) {
  const { fields } = useAppServices();
  const typed = field.typed;
  if (typed.kind === 'select' || typed.kind === 'multiSelect') {
    return <SelectOptionsEditor fieldId={field.id} options={typed.config.options} />;
  }
  if (typed.kind === 'relation') {
    return (
      <div className="grid gap-1.5">
        <span className="text-sm font-medium">Related collection</span>
        <RelationTargetSelect
          value={typed.config.targetCollectionId}
          collections={collections}
          onChange={(id) => void fields.updateConfig(field.id, encodeRelationConfig(id))}
        />
      </div>
    );
  }
  return <FieldConfigEditor field={field} />;
}

function RelationTargetSelect(props: {
  value: string | undefined;
  collections: readonly Collection[];
  onChange: (id: string) => void;
}) {
  return (
    <Select value={props.value ?? ''} onValueChange={props.onChange}>
      <SelectTrigger aria-label="Related collection" className="w-48">
        <SelectValue placeholder="Relates to…" />
      </SelectTrigger>
      <SelectContent>
        {props.collections.map((collection) => (
          <SelectItem key={collection.id} value={collection.id}>
            {collection.name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

function AddFieldRow(props: {
  collectionId: string;
  collections: readonly Collection[];
  onAdded: (id: string, isSelect: boolean) => void;
}) {
  const { fields, fieldTypes } = useAppServices();
  const [name, setName] = useState('');
  const [type, setType] = useState(() => new FieldTypeChoice(textFieldType));
  const [target, setTarget] = useState<string | undefined>();
  const isRelation = type.base.kind === 'relation';
  const isSelect = type.variant === undefined && (type.base.kind === 'select' || type.base.kind === 'multiSelect');
  // A relation field is useless without a target - adding waits until one's picked.
  const canAdd = name.trim().length > 0 && (!isRelation || target !== undefined);

  async function add() {
    if (!canAdd) return;
    let config: string | null = null;
    if (isRelation && target !== undefined) config = encodeRelationConfig(target);
    // Usable right away - options are added in the field's settings or from the option picker.
    if (isSelect) config = encodeSelectConfig([]);
    const id = await fields.create({
      collectionId: props.collectionId,
      name: name.trim(),
      type: type.base,
      ...(type.variant === undefined ? {} : { variant: type.variant }),
      config,
    });
    setName('');
    setType(new FieldTypeChoice(textFieldType));
    setTarget(undefined);
    props.onAdded(id, isSelect);
  }

  return (
    <div className="mt-2 flex flex-wrap items-center gap-2 border-t pt-3 sm:flex-nowrap sm:pl-7">
      <div className="relative min-w-0 flex-1">
        <Plus className="pointer-events-none absolute top-2 left-2.5 size-4 text-muted-foreground" />
        <Input
          aria-label="New field name"
          placeholder="New field name"
          className="pl-8"
          value={name}
          onChange={(event) => setName(event.target.value)}
          onKeyDown={(event) => event.key === 'Enter' && void add()}
        />
      </div>
      <FieldTypePicker
        value={type}
        choices={fieldTypes.choices.filter((choice) => choice.base.kind !== 'unsupported')}
        onChange={setType}
      />
      {isRelation && <RelationTargetSelect value={target} collections={props.collections} onChange={setTarget} />}
      <Button variant="secondary" disabled={!canAdd} onClick={() => void add()}>
        Add field
      </Button>
    </div>
  );
}
