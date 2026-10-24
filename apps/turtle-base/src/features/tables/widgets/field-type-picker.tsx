import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectTrigger,
  SelectValue,
} from '../../../core/ui/select.tsx';
import type { FieldTypeChoice } from '../data/field-type-registry.ts';
import { FieldTypeIcon } from './field-type-icon.tsx';

const groups = ['Basic', 'Choice', 'Formats', 'Advanced'] as const;

function groupOf(choice: FieldTypeChoice): (typeof groups)[number] {
  if (choice.variant !== undefined) return 'Formats';
  switch (choice.base.kind) {
    case 'select':
    case 'multiSelect':
      return 'Choice';
    case 'relation':
    case 'unsupported':
      return 'Advanced';
    default:
      return 'Basic';
  }
}

/** Picks a field type - base types and variants, grouped and sorted by name within a group. */
export function FieldTypePicker(props: {
  value: FieldTypeChoice;
  choices: readonly FieldTypeChoice[];
  onChange: (choice: FieldTypeChoice) => void;
}) {
  return (
    <Select
      value={props.value.key}
      onValueChange={(key) => {
        const choice = props.choices.find((c) => c.key === key);
        if (choice !== undefined) props.onChange(choice);
      }}
    >
      <SelectTrigger aria-label="Field type" className="w-44 shrink-0">
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {groups.map((group) => {
          const inGroup = props.choices
            .filter((choice) => groupOf(choice) === group)
            .toSorted((a, b) => a.label.toLowerCase().localeCompare(b.label.toLowerCase()));
          if (inGroup.length === 0) return null;
          return (
            <SelectGroup key={group}>
              <SelectLabel>{group}</SelectLabel>
              {inGroup.map((choice) => (
                <SelectItem key={choice.key} value={choice.key}>
                  <FieldTypeIcon base={choice.base} variantId={choice.variant?.id} />
                  {choice.label}
                </SelectItem>
              ))}
            </SelectGroup>
          );
        })}
      </SelectContent>
    </Select>
  );
}
