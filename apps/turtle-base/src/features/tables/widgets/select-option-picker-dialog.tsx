import { Check, Plus } from 'lucide-react';
import { useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { useDbQuery } from '../../../core/database/use-db-query.ts';
import { Button } from '../../../core/ui/button.tsx';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '../../../core/ui/dialog.tsx';
import { Input } from '../../../core/ui/input.tsx';
import { decodeSelectOptions, nextOptionColor, resolveSelectValue } from '../data/select-field.ts';
import { SelectOptionChip } from './select-option-chip.tsx';

/**
 * Picks the options of a select (one, closes on pick) or multi-select (any,
 * confirmed with Done) field. Typing filters the options; a name that isn't
 * one yet can be created right here.
 */
export function SelectOptionPickerDialog(props: {
  fieldId: string;
  multiple: boolean;
  selectedIds: readonly string[];
  onOpenChange: (open: boolean) => void;
  onPick: (ids: readonly string[]) => void | Promise<void>;
}) {
  return (
    <Dialog open onOpenChange={props.onOpenChange}>
      <DialogContent fullScreenWhenNarrow className="sm:max-w-md">
        <Picker {...props} />
      </DialogContent>
    </Dialog>
  );
}

function Picker(props: {
  fieldId: string;
  multiple: boolean;
  selectedIds: readonly string[];
  onOpenChange: (open: boolean) => void;
  onPick: (ids: readonly string[]) => void | Promise<void>;
}) {
  const { fields } = useAppServices();
  const { data: field } = useDbQuery({
    tables: ['fields'],
    key: [props.fieldId],
    query: () => fields.byId(props.fieldId),
  });
  const [selectedIds, setSelectedIds] = useState(props.selectedIds);
  const [query, setQuery] = useState('');
  const options = decodeSelectOptions(field?.config ?? null);
  const name = query.trim();
  const lower = name.toLowerCase();
  const matches = options.filter((option) => option.name.toLowerCase().includes(lower));
  const canCreate = name.length > 0 && !options.some((option) => option.name.toLowerCase() === lower);
  const selected = resolveSelectValue(options, selectedIds);

  async function pick(ids: readonly string[]) {
    await props.onPick(ids);
    props.onOpenChange(false);
  }

  function toggle(optionId: string) {
    if (!props.multiple) {
      const isCurrent = selectedIds.length === 1 && selectedIds[0] === optionId;
      void pick(isCurrent ? [] : [optionId]);
      return;
    }
    setSelectedIds((ids) => (ids.includes(optionId) ? ids.filter((id) => id !== optionId) : [...ids, optionId]));
  }

  async function create() {
    const option = await fields.addSelectOption(props.fieldId, name);
    setQuery('');
    toggle(option.id);
  }

  return (
    <div className="grid gap-3 max-sm:flex max-sm:min-h-0 max-sm:flex-1 max-sm:flex-col">
      <DialogHeader>
        <DialogTitle>{field?.name}</DialogTitle>
      </DialogHeader>
      {selected.length > 0 && (
        <div className="flex flex-wrap gap-1">
          {selected.map((option) => (
            <SelectOptionChip
              key={option.id}
              option={option}
              onRemove={() => (props.multiple ? toggle(option.id) : void pick([]))}
            />
          ))}
        </div>
      )}
      <Input
        autoFocus
        aria-label="Search or create an option"
        placeholder="Search or create an option"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        onKeyDown={(event) => {
          if (event.key !== 'Enter') return;
          event.preventDefault();
          const [first] = matches;
          if (canCreate) void create();
          else if (first !== undefined && name.length > 0) toggle(first.id);
        }}
      />
      <div className="grid max-h-72 content-start gap-0.5 overflow-auto max-sm:max-h-none max-sm:min-h-0 max-sm:flex-1">
        {options.length === 0 && !canCreate && (
          <p className="py-4 text-center text-sm text-muted-foreground">No options yet - type to create one</p>
        )}
        {matches.map((option) => (
          <Button key={option.id} variant="ghost" className="justify-between" onClick={() => toggle(option.id)}>
            <SelectOptionChip option={option} />
            {selectedIds.includes(option.id) && <Check />}
          </Button>
        ))}
        {canCreate && (
          <Button variant="ghost" className="justify-start" onClick={() => void create()}>
            <Plus />
            Create
            <SelectOptionChip option={{ id: '', name, color: nextOptionColor(options) }} />
          </Button>
        )}
      </div>
      {props.multiple && (
        <DialogFooter>
          <Button variant="outline" onClick={() => props.onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={() => void pick(selected.map((option) => option.id))}>Done</Button>
        </DialogFooter>
      )}
    </div>
  );
}
