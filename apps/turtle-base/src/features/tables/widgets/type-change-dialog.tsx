import type { TypeChangePlan } from '../data/field-conversion.ts';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '../../../core/ui/alert-dialog.tsx';

/** Whether a type change touches values the user should know about before it happens. */
export function needsTypeChangeConfirmation(plan: TypeChangePlan): boolean {
  return plan.invalidCount > 0 || (plan.mode === 'rewrite' && plan.valueCount > 0);
}

function values(count: number): string {
  return count === 1 ? '1 value' : `${count} values`;
}

/** What a type change does to the values (see FieldsRepository.planTypeChange), to confirm or cancel. */
export function TypeChangeDialog(props: {
  plan: TypeChangePlan;
  typeLabel: string;
  onConfirm: () => void | Promise<void>;
  onCancel: () => void;
}) {
  const { plan, typeLabel } = props;
  const lines = [
    plan.mode === 'rewrite'
      ? `${values(plan.valueCount)} will be converted to ${typeLabel}.`
      : 'Existing values are kept as they are.',
  ];
  if (plan.invalidCount > 0) {
    const samples = plan.invalidSamples.map((sample) => `"${sample}"`).join(', ');
    lines.push(
      `${plan.invalidCount} of ${values(plan.valueCount)} won't fit ${typeLabel} (e.g. ${samples}) and will be flagged as invalid${plan.mode === 'rewrite' ? ', kept as plain text' : ''}.`,
    );
  }
  return (
    <AlertDialog open onOpenChange={(open) => !open && props.onCancel()}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Change type to {typeLabel}?</AlertDialogTitle>
          {lines.map((line) => (
            <AlertDialogDescription key={line}>{line}</AlertDialogDescription>
          ))}
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction onClick={() => void props.onConfirm()}>Change type</AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
