import { ArrowLeft, Trash2 } from 'lucide-react';
import { useId, useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { useDbQuery } from '../../../core/database/use-db-query.ts';
import type { Collection } from '../../../core/database/schema.ts';
import { Button } from '../../../core/ui/button.tsx';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '../../../core/ui/card.tsx';
import { Input } from '../../../core/ui/input.tsx';
import { Label } from '../../../core/ui/label.tsx';
import { ConfirmDialog } from '../../shell/widgets/confirm-dialog.tsx';
import { FieldsEditor } from './fields-editor.tsx';

/**
 * Edits a collection - its icon, name, title column label and fields - in the
 * content area, so the sidebar stays visible. `onDone` goes back to the
 * entries, `onDeleted` is called after deleting the collection itself.
 */
export function CollectionEditPage(props: { collectionId: string; onDone: () => void; onDeleted: () => void }) {
  const { collections } = useAppServices();
  const [deleting, setDeleting] = useState(false);
  const { data: collection } = useDbQuery({
    tables: ['collections'],
    key: [props.collectionId],
    query: () => collections.byId(props.collectionId),
  });

  return (
    <div className="mx-auto grid w-full max-w-3xl gap-4 p-4 sm:p-6">
      <header className="flex items-center gap-2">
        <Button variant="ghost" size="icon" aria-label="Back" onClick={props.onDone}>
          <ArrowLeft />
        </Button>
        <h1 className="flex-1 text-xl font-semibold">Edit collection</h1>
        <Button variant="ghost" size="icon" aria-label="Delete this collection" onClick={() => setDeleting(true)}>
          <Trash2 />
        </Button>
      </header>
      {collection !== undefined && (
        <>
          {/* Keyed, so the inputs start from the stored values again when another collection opens. */}
          <CollectionCard key={collection.id} collection={collection} />
          <Card>
            <CardHeader>
              <CardTitle>Fields</CardTitle>
              <CardDescription>
                Drag to reorder. The type decides how values are entered, checked and shown.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <FieldsEditor collectionId={collection.id} spaceId={collection.space_id} />
            </CardContent>
          </Card>
        </>
      )}
      <ConfirmDialog
        open={deleting}
        title="Delete this collection?"
        message="Its entries will stop being shown until it's restored - there's no trash to restore it from yet."
        onOpenChange={setDeleting}
        onConfirm={async () => {
          await collections.softDelete(props.collectionId);
          props.onDeleted();
        }}
      />
    </div>
  );
}

function CollectionCard({ collection }: { collection: Collection }) {
  const { collections } = useAppServices();
  const id = useId();
  const [icon, setIcon] = useState(collection.icon ?? '');
  const [name, setName] = useState(collection.name);
  const [titleLabel, setTitleLabel] = useState(collection.title_field_label ?? '');

  function saveIcon() {
    const trimmed = icon.trim();
    if (trimmed !== (collection.icon ?? ''))
      void collections.setIcon(collection.id, trimmed.length === 0 ? null : trimmed);
  }

  function saveName() {
    const trimmed = name.trim();
    if (trimmed.length > 0 && trimmed !== collection.name) void collections.rename(collection.id, trimmed);
  }

  // Unlike the name, empty is valid here - it goes back to the "Name" default.
  function saveTitleLabel() {
    const trimmed = titleLabel.trim();
    if (trimmed !== (collection.title_field_label ?? '')) {
      void collections.setTitleFieldLabel(collection.id, trimmed.length === 0 ? null : trimmed);
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Collection</CardTitle>
      </CardHeader>
      <CardContent className="grid gap-4">
        <div className="grid gap-1.5">
          <Label htmlFor={`${id}-name`}>Icon and name</Label>
          <div className="flex gap-2">
            <Input
              aria-label="Icon"
              placeholder="🙂"
              className="w-12 text-center text-lg"
              value={icon}
              onChange={(event) => setIcon(event.target.value)}
              onBlur={saveIcon}
              onKeyDown={(event) => event.key === 'Enter' && saveIcon()}
            />
            <Input
              id={`${id}-name`}
              value={name}
              onChange={(event) => setName(event.target.value)}
              onBlur={saveName}
              onKeyDown={(event) => event.key === 'Enter' && saveName()}
            />
          </div>
        </div>
        <div className="grid gap-1.5">
          <Label htmlFor={`${id}-title`}>Name column label</Label>
          <Input
            id={`${id}-title`}
            placeholder="Name"
            value={titleLabel}
            onChange={(event) => setTitleLabel(event.target.value)}
            onBlur={saveTitleLabel}
            onKeyDown={(event) => event.key === 'Enter' && saveTitleLabel()}
          />
          <p className="text-xs text-muted-foreground">The heading of the built-in column every entry has.</p>
        </div>
      </CardContent>
    </Card>
  );
}
