import { cn } from 'cn';
import { useState, type KeyboardEvent, type ReactNode } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import type { Attachment } from '../../../core/database/schema.ts';
import { Checkbox } from '../../../core/ui/checkbox.tsx';
import { AttachmentThumbnail } from '../../files/widgets/attachment-thumbnail.tsx';
import type { Json } from '../data/base-field-type.ts';
import { decodeRelationValue } from '../data/relation-field.ts';
import type { ResolvedField } from '../data/resolved-field.ts';
import { encodeSelectValue, resolveSelectValue, type SelectOption } from '../data/select-field.ts';
import { SelectOptionChip } from './select-option-chip.tsx';
import { SelectOptionPickerDialog } from './select-option-picker-dialog.tsx';

/**
 * One field's value of an entry, shown by its type and edited in place: typed
 * in for text, number, date and location (checked like the user's input
 * anywhere, see ResolvedField.parse), toggled for a checkbox, picked for a
 * select. Relations and files are shown only - they're edited on the entry's
 * page. A stored value that doesn't fit the field's type (e.g. after a type
 * change) is flagged, never hidden.
 */
export function FieldValueCell(props: {
  entryId: string;
  field: ResolvedField;
  raw: unknown;
  /** Titles of related entries by id, for relation fields. */
  relatedTitles?: ReadonlyMap<string, string>;
  /** The entry's attachments in this field, for files fields. */
  attachments?: readonly Attachment[];
}) {
  const { pages } = useAppServices();
  const { entryId, field, raw } = props;
  const save = (stored: Json) => pages.setPropertyValue(entryId, field.id, stored);

  switch (field.typed.kind) {
    case 'checkbox':
      return (
        <Checkbox
          aria-label={field.name}
          checked={field.valueOf(raw) === true}
          onCheckedChange={(checked) => {
            const parsed = field.parse(String(checked === true));
            if (parsed.kind === 'value') void save(parsed.stored);
          }}
        />
      );
    case 'select':
    case 'multiSelect':
      return (
        <SelectCell
          {...props}
          options={field.typed.config.options}
          multiple={field.typed.kind === 'multiSelect'}
          onSave={save}
        />
      );
    case 'relation': {
      const titles = decodeRelationValue(raw).map((id) => props.relatedTitles?.get(id) ?? '?');
      return <span className="truncate">{titles.join(', ')}</span>;
    }
    case 'files':
      return (
        <span className="flex gap-1 overflow-hidden">
          {(props.attachments ?? []).map((attachment) => (
            <AttachmentThumbnail key={attachment.id} attachment={attachment} />
          ))}
        </span>
      );
    case 'unsupported':
      return <ValueText field={field} raw={raw} />;
    default:
      return (
        <InlineTextEditor<Json>
          label={field.name}
          value={field.plain(raw)}
          parse={(text) => {
            const parsed = field.parse(text);
            return parsed.kind === 'error' ? { error: parsed.message } : { value: parsed.stored };
          }}
          onSave={save}
        >
          <ValueText field={field} raw={raw} />
        </InlineTextEditor>
      );
  }
}

/** The display text - in red when it doesn't fit the field's type, as a link when it is one. */
function ValueText({ field, raw }: { field: ResolvedField; raw: unknown }) {
  const { platform } = useAppServices();
  const text = field.display(raw);
  if (text.length === 0) return null;
  const error = field.errorFor(raw);
  if (error !== undefined) {
    return (
      <span className="truncate text-destructive" title={error}>
        {text}
      </span>
    );
  }
  const link = field.linkFor(raw);
  if (link === undefined) return <span className="truncate">{text}</span>;
  return (
    <a
      href={link.href}
      className="truncate text-primary underline underline-offset-2"
      onClick={(event) => {
        // The cell would start editing otherwise; the window never navigates away from the app.
        event.preventDefault();
        event.stopPropagation();
        void platform.openExternal(link.href);
      }}
    >
      {text}
    </a>
  );
}

function SelectCell(props: {
  entryId: string;
  field: ResolvedField;
  raw: unknown;
  options: readonly SelectOption[];
  multiple: boolean;
  onSave: (stored: Json) => Promise<void>;
}) {
  const [picking, setPicking] = useState(false);
  const selected = resolveSelectValue(props.options, props.field.valueOf(props.raw));
  return (
    <>
      <button
        type="button"
        aria-label={props.field.name}
        onClick={() => setPicking(true)}
        className="flex size-full items-center gap-1 overflow-hidden text-left"
      >
        {selected.map((option) => (
          <SelectOptionChip key={option.id} option={option} />
        ))}
      </button>
      {picking && (
        <SelectOptionPickerDialog
          fieldId={props.field.id}
          multiple={props.multiple}
          selectedIds={selected.map((option) => option.id)}
          onOpenChange={setPicking}
          onPick={(ids) => props.onSave(encodeSelectValue(ids, props.multiple))}
        />
      )}
    </>
  );
}

/**
 * Shows `children` until clicked (or focused and Enter pressed), then an input
 * with `value`. Enter or leaving the input saves what `parse` accepts; an
 * error stays in the input, shown, until fixed or Escape cancels.
 */
export function InlineTextEditor<T>(props: {
  label: string;
  value: string;
  parse: (text: string) => { value: T } | { error: string };
  onSave: (value: T) => Promise<void>;
  children: ReactNode;
  className?: string;
}) {
  const [draft, setDraft] = useState<string | undefined>();
  const [error, setError] = useState<string | undefined>();

  async function commit() {
    if (draft === undefined) return;
    if (draft === props.value) {
      setDraft(undefined);
      return;
    }
    const parsed = props.parse(draft);
    if ('error' in parsed) {
      setError(parsed.error);
      return;
    }
    await props.onSave(parsed.value);
    setDraft(undefined);
    setError(undefined);
  }

  function cancel() {
    setDraft(undefined);
    setError(undefined);
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === 'Enter') void commit();
    if (event.key === 'Escape') cancel();
  }

  if (draft === undefined) {
    return (
      <button
        type="button"
        aria-label={props.label}
        onClick={() => setDraft(props.value)}
        className={cn('flex size-full min-w-0 items-center text-left', props.className)}
      >
        {props.children}
      </button>
    );
  }
  return (
    <input
      autoFocus
      aria-label={props.label}
      aria-invalid={error !== undefined}
      title={error}
      value={draft}
      onChange={(event) => {
        setDraft(event.target.value);
        setError(undefined);
      }}
      onKeyDown={onKeyDown}
      onBlur={() => void commit()}
      className="size-full min-w-0 rounded-sm bg-background px-1 outline-2 outline-ring aria-invalid:outline-destructive"
    />
  );
}
