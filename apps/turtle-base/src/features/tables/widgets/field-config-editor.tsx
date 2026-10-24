import { useId, useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { Button } from '../../../core/ui/button.tsx';
import { Input } from '../../../core/ui/input.tsx';
import { Label } from '../../../core/ui/label.tsx';
import { FileAccept } from '../../files/data/file-accept.ts';
import {
  filesAcceptKey,
  filesMaxFilesKey,
  formatPlainNumber,
  numberMaxKey,
  numberMinKey,
  textPatternKey,
  tryParsePattern,
} from '../data/base-field-type.ts';
import { parseNumber } from '../data/field-validation.ts';
import type { ResolvedField } from '../data/resolved-field.ts';

/**
 * The type-specific settings of text, number and files fields. Variants have
 * none - a variant fixes the semantics, so e.g. a URL field has no pattern to
 * edit. Select and relation settings are in the fields editor itself.
 */
export function FieldConfigEditor({ field }: { field: ResolvedField }) {
  const { fields } = useAppServices();
  if (field.variant !== undefined) return null;
  const typed = field.typed;
  switch (typed.kind) {
    case 'text':
      return (
        <ConfigInput
          label="Pattern"
          placeholder="e.g. [A-Z]{3}-\d+"
          description="A regular expression every value must fully match. Leave empty to allow any text."
          initialValue={typed.config.pattern?.source ?? ''}
          validate={(value) =>
            value.length === 0 || tryParsePattern(value) !== undefined ? undefined : 'Not a valid regular expression'
          }
          onSave={(value) =>
            fields.updateConfigValues(field.id, { [textPatternKey]: value.length === 0 ? null : value })
          }
        />
      );
    case 'number': {
      return (
        <div className="flex flex-wrap gap-3">
          {(['min', 'max'] as const).map((bound) => {
            const current = typed.config[bound];
            return (
              <ConfigInput
                key={bound}
                className="w-28"
                label={bound === 'min' ? 'Min' : 'Max'}
                initialValue={current === undefined ? '' : formatPlainNumber(current)}
                validate={validateNumber}
                onSave={(value) =>
                  fields.updateConfigValues(field.id, {
                    [bound === 'min' ? numberMinKey : numberMaxKey]: parseNumber(value) ?? null,
                  })
                }
              />
            );
          })}
        </div>
      );
    }
    case 'files':
      return <FilesConfigEditor field={field} accept={typed.config.accept} maxFiles={typed.config.maxFiles} />;
    default:
      return null;
  }
}

function validateNumber(value: string): string | undefined {
  return value.length === 0 || parseNumber(value) !== undefined ? undefined : 'Not a number';
}

const presets: readonly (readonly [string, FileAccept])[] = [
  ['Any file', FileAccept.any],
  ['Images', FileAccept.images],
  ['PDF', FileAccept.pdf],
];

function FilesConfigEditor(props: { field: ResolvedField; accept: FileAccept; maxFiles: number | undefined }) {
  const { fields } = useAppServices();
  const saveAccept = (accept: FileAccept) =>
    fields.updateConfigValues(props.field.id, { [filesAcceptKey]: accept.isAny ? null : accept.patterns });
  return (
    <div className="grid gap-3">
      <div className="grid gap-1.5">
        <span className="text-sm font-medium">Allowed files</span>
        <div className="flex flex-wrap gap-2">
          {presets.map(([label, accept]) => (
            <Button
              key={label}
              size="sm"
              variant={props.accept.equals(accept) ? 'secondary' : 'outline'}
              onClick={() => void saveAccept(accept)}
            >
              {label}
            </Button>
          ))}
        </div>
      </div>
      <ConfigInput
        key={props.accept.toText()}
        label="Custom"
        placeholder="e.g. image/*, application/pdf, .xml"
        description="MIME types, wildcards like image/* or extensions like .xml, separated by commas."
        initialValue={props.accept.toText()}
        validate={() => undefined}
        onSave={(value) => saveAccept(FileAccept.parse(value))}
      />
      <ConfigInput
        className="w-40"
        label="Max files"
        placeholder="No limit"
        initialValue={props.maxFiles?.toString() ?? ''}
        validate={(value) => (value.length === 0 || /^[1-9]\d*$/.test(value) ? undefined : 'A whole number from 1')}
        onSave={(value) =>
          fields.updateConfigValues(props.field.id, { [filesMaxFilesKey]: value.length === 0 ? null : Number(value) })
        }
      />
    </div>
  );
}

/** A setting saved when the input is left or Enter is pressed - only if `validate` accepts it. */
function ConfigInput(props: {
  label: string;
  initialValue: string;
  validate: (value: string) => string | undefined;
  onSave: (value: string) => void | Promise<void>;
  placeholder?: string;
  description?: string;
  className?: string;
}) {
  const id = useId();
  const [value, setValue] = useState(props.initialValue);
  const error = props.validate(value.trim());
  const save = () => {
    const trimmed = value.trim();
    if (error === undefined && trimmed !== props.initialValue) void props.onSave(trimmed);
  };
  return (
    <div className={props.className ?? 'grid gap-1.5'}>
      <Label htmlFor={id} className="mb-1.5">
        {props.label}
      </Label>
      <Input
        id={id}
        value={value}
        placeholder={props.placeholder}
        aria-invalid={error !== undefined}
        onChange={(event) => setValue(event.target.value)}
        onBlur={save}
        onKeyDown={(event) => event.key === 'Enter' && save()}
      />
      {error !== undefined ? (
        <p className="mt-1 text-xs text-destructive">{error}</p>
      ) : (
        props.description !== undefined && <p className="mt-1 text-xs text-muted-foreground">{props.description}</p>
      )}
    </div>
  );
}
