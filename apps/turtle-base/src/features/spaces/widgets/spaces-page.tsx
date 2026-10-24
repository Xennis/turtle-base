import { useState, type FormEvent } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
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
    <main className="spaces-page">
      <h1>Spaces</h1>
      {isPending && <p>Loading…</p>}
      {error !== null && <p role="alert">Couldn't load the spaces: {String(error)}</p>}
      {data?.length === 0 && <p className="empty">No spaces yet - create your first one.</p>}
      <ul>
        {data?.map((space) => (
          <li key={space.id}>
            <span className="icon">{space.icon ?? '📁'}</span>
            {space.name}
          </li>
        ))}
      </ul>
      <form onSubmit={(event) => void add(event)}>
        <input
          aria-label="Space name"
          placeholder="New space"
          value={name}
          onChange={(event) => setName(event.target.value)}
        />
        <button type="submit">Add space</button>
      </form>
    </main>
  );
}
