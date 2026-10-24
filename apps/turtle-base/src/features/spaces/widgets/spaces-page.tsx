import { useState, type FormEvent } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { Button } from '../../../core/ui/button.tsx';
import { Input } from '../../../core/ui/input.tsx';
import { useDbQuery } from '../../../core/database/use-db-query.ts';
import { SpacesRepository } from '../data/spaces-repository.ts';

/** The spaces in the database, and a way to add one - the first page of the TypeScript app. */
export function SpacesPage() {
  const { database } = useAppServices();
  const spaces = new SpacesRepository(database);
  const { data, error, isPending } = useDbQuery({ tables: ['spaces'], key: [], query: () => spaces.listActive() });
  const [name, setName] = useState('');

  async function add(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const trimmed = name.trim();
    if (trimmed.length === 0) return;
    await spaces.create({ name: trimmed });
    setName('');
  }

  return (
    <main className="mx-auto my-12 max-w-xl px-4">
      <h1 className="mb-4 text-2xl font-semibold">Spaces</h1>
      {isPending && <p className="text-muted-foreground">Loading…</p>}
      {error !== null && <p role="alert">Couldn't load the spaces: {String(error)}</p>}
      {data?.length === 0 && <p className="text-muted-foreground">No spaces yet - create your first one.</p>}
      <ul>
        {data?.map((space) => (
          <li key={space.id} className="flex gap-2 border-b py-2">
            <span>{space.icon ?? '📁'}</span>
            {space.name}
          </li>
        ))}
      </ul>
      <form className="mt-4 flex gap-2" onSubmit={(event) => void add(event)}>
        <Input
          aria-label="Space name"
          placeholder="New space"
          value={name}
          onChange={(event) => setName(event.target.value)}
        />
        <Button type="submit">Add space</Button>
      </form>
    </main>
  );
}
