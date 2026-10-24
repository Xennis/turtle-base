import { useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { useDbQuery } from '../../../core/database/use-db-query.ts';
import { Button } from '../../../core/ui/button.tsx';
import { Checkbox } from '../../../core/ui/checkbox.tsx';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '../../../core/ui/dialog.tsx';
import { Input } from '../../../core/ui/input.tsx';
import { Label } from '../../../core/ui/label.tsx';

/** Picks the related entries of a relation field among the target collection's entries, searchable by title. */
export function RelationPickerDialog(props: {
  targetCollectionId: string;
  selectedIds: readonly string[];
  onOpenChange: (open: boolean) => void;
  onPick: (ids: readonly string[]) => void | Promise<void>;
}) {
  const { pages } = useAppServices();
  const [selected, setSelected] = useState<ReadonlySet<string>>(new Set(props.selectedIds));
  const [query, setQuery] = useState('');
  const { data: entries = [] } = useDbQuery({
    tables: ['pages'],
    key: ['collection', props.targetCollectionId],
    query: () => pages.listActiveInCollection(props.targetCollectionId),
  });
  const matches = entries.filter((entry) => entry.title.toLowerCase().includes(query.trim().toLowerCase()));

  async function done() {
    // In the order they were picked before, new ones after.
    const kept = props.selectedIds.filter((id) => selected.has(id));
    await props.onPick([...kept, ...[...selected].filter((id) => !kept.includes(id))]);
    props.onOpenChange(false);
  }

  function toggle(id: string, checked: boolean) {
    setSelected((ids) => {
      const next = new Set(ids);
      if (checked) next.add(id);
      else next.delete(id);
      return next;
    });
  }

  return (
    <Dialog open onOpenChange={props.onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Select related entries</DialogTitle>
        </DialogHeader>
        <Input
          autoFocus
          aria-label="Search"
          placeholder="Search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
        />
        <div className="grid max-h-72 gap-1 overflow-auto">
          {matches.length === 0 && <p className="py-4 text-center text-sm text-muted-foreground">No entries found</p>}
          {matches.map((entry) => (
            <Label key={entry.id} className="flex items-center gap-2 rounded-md px-2 py-1.5 font-normal hover:bg-muted">
              <Checkbox
                checked={selected.has(entry.id)}
                onCheckedChange={(checked) => toggle(entry.id, checked === true)}
              />
              {entry.title.length === 0 ? 'Untitled' : entry.title}
            </Label>
          ))}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => props.onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={() => void done()}>Done</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
