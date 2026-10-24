import { optionColors } from '@turtle-base/plugin-api';
import { Plus, X } from 'lucide-react';
import { useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { Button } from '../../../core/ui/button.tsx';
import { Input } from '../../../core/ui/input.tsx';
import { Popover, PopoverContent, PopoverTrigger } from '../../../core/ui/popover.tsx';
import { ConfirmDialog } from '../../shell/widgets/confirm-dialog.tsx';
import type { SelectOption } from '../data/select-field.ts';
import { OptionColorDot, optionColorLabel } from './select-option-chip.tsx';

/** A select field's options: rename, recolor and delete each, add new ones. */
export function SelectOptionsEditor(props: { fieldId: string; options: readonly SelectOption[] }) {
  const { fields } = useAppServices();
  const [name, setName] = useState('');

  async function add() {
    const trimmed = name.trim();
    if (trimmed.length === 0) return;
    await fields.addSelectOption(props.fieldId, trimmed);
    setName('');
  }

  return (
    <div className="grid gap-1.5">
      {props.options.map((option) => (
        <OptionRow key={option.id} fieldId={props.fieldId} option={option} />
      ))}
      <div className="flex items-center gap-1">
        <Input
          aria-label="New option"
          placeholder="Add option"
          value={name}
          onChange={(event) => setName(event.target.value)}
          onKeyDown={(event) => event.key === 'Enter' && void add()}
        />
        <Button variant="ghost" size="icon" aria-label="Add option" onClick={() => void add()}>
          <Plus />
        </Button>
      </div>
    </div>
  );
}

function OptionRow({ fieldId, option }: { fieldId: string; option: SelectOption }) {
  const { fields } = useAppServices();
  const [name, setName] = useState(option.name);
  const [colorsOpen, setColorsOpen] = useState(false);
  const [deleting, setDeleting] = useState(false);

  function saveName() {
    const trimmed = name.trim();
    if (trimmed.length > 0 && trimmed !== option.name)
      void fields.updateSelectOption(fieldId, { ...option, name: trimmed });
  }

  return (
    <div className="flex items-center gap-1">
      <Popover open={colorsOpen} onOpenChange={setColorsOpen}>
        <PopoverTrigger asChild>
          <Button variant="ghost" size="icon" aria-label={`Color of ${option.name}`}>
            <OptionColorDot color={option.color} />
          </Button>
        </PopoverTrigger>
        <PopoverContent className="grid w-auto grid-cols-3 gap-1 p-2">
          {optionColors.map((color) => (
            <Button
              key={color}
              variant="ghost"
              size="icon"
              aria-label={optionColorLabel(color)}
              aria-pressed={color === option.color}
              className="aria-pressed:ring-2 aria-pressed:ring-ring"
              onClick={() => {
                setColorsOpen(false);
                void fields.updateSelectOption(fieldId, { ...option, color });
              }}
            >
              <OptionColorDot color={color} className="size-4.5" />
            </Button>
          ))}
        </PopoverContent>
      </Popover>
      <Input
        aria-label="Option name"
        value={name}
        onChange={(event) => setName(event.target.value)}
        onBlur={saveName}
        onKeyDown={(event) => event.key === 'Enter' && saveName()}
      />
      <Button variant="ghost" size="icon" aria-label={`Delete option ${option.name}`} onClick={() => setDeleting(true)}>
        <X className="text-muted-foreground" />
      </Button>
      <ConfirmDialog
        open={deleting}
        title={`Delete option "${option.name}"?`}
        message="Entries using it will no longer show this value."
        onOpenChange={setDeleting}
        onConfirm={() => fields.removeSelectOption(fieldId, option.id)}
      />
    </div>
  );
}
