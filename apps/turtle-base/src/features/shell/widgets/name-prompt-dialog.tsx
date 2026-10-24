import { useState, type FormEvent } from 'react';

import { Button } from '../../../core/ui/button.tsx';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '../../../core/ui/dialog.tsx';
import { Input } from '../../../core/ui/input.tsx';

/** Asks for a name, e.g. of a new space - `onSubmit` gets it trimmed, never empty. */
export function NamePromptDialog(props: {
  open: boolean;
  title: string;
  initialValue?: string;
  confirmLabel?: string;
  onOpenChange: (open: boolean) => void;
  onSubmit: (name: string) => void | Promise<void>;
}) {
  return (
    <Dialog open={props.open} onOpenChange={props.onOpenChange}>
      <DialogContent className="sm:max-w-sm">
        {/* Mounted per opening, so the field starts from initialValue again. */}
        {props.open && <NameForm {...props} />}
      </DialogContent>
    </Dialog>
  );
}

function NameForm(props: {
  title: string;
  initialValue?: string;
  confirmLabel?: string;
  onOpenChange: (open: boolean) => void;
  onSubmit: (name: string) => void | Promise<void>;
}) {
  const [name, setName] = useState(props.initialValue ?? '');
  const trimmed = name.trim();

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (trimmed.length === 0) return;
    await props.onSubmit(trimmed);
    props.onOpenChange(false);
  }

  return (
    <form className="grid gap-4" onSubmit={(event) => void submit(event)}>
      <DialogHeader>
        <DialogTitle>{props.title}</DialogTitle>
      </DialogHeader>
      <Input aria-label="Name" autoFocus value={name} onChange={(event) => setName(event.target.value)} />
      <DialogFooter>
        <Button type="button" variant="outline" onClick={() => props.onOpenChange(false)}>
          Cancel
        </Button>
        <Button type="submit" disabled={trimmed.length === 0}>
          {props.confirmLabel ?? 'Save'}
        </Button>
      </DialogFooter>
    </form>
  );
}
